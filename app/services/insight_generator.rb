# frozen_string_literal: true

# InsightGenerator - 발행된 리포트에서 SEO 최적화 블로그 포스트 자동 생성
#
# 사용법:
#   InsightGenerator.generate_from_report!(report)
#
class InsightGenerator
  def self.generate_from_report!(report)
    new(report).generate!
  end

  def initialize(report)
    @report = report
    @game = report.game
  end

  def generate!
    # 이미 이 리포트에서 생성된 인사이트가 있으면 스킵
    if Insight.exists?(report_id: @report.id)
      Rails.logger.info("[InsightGenerator] Report ##{@report.id} already has an insight. Skipping.")
      return nil
    end

    prompt = build_seo_prompt
    raw_content = call_llm(prompt)

    if raw_content.blank?
      Rails.logger.warn("[InsightGenerator] LLM returned empty content for Report ##{@report.id}")
      return nil
    end

    create_insight(raw_content)
  rescue => e
    Rails.logger.error("[InsightGenerator] Failed for Report ##{@report.id}: #{e.message}")
    nil
  end

  private

  def build_seo_prompt
    game_date_str = @game.game_date&.in_time_zone("Asia/Seoul")&.strftime("%Y년 %m월 %d일") || "오늘"
    league = @game.league_name.presence || @game.league.presence || "NBA"
    home = @game.home_team
    away = @game.away_team
    home_record = @game.home_record.present? ? "(#{@game.home_record})" : ""
    away_record = @game.away_record.present? ? "(#{@game.away_record})" : ""

    schedule_notes = []
    schedule_notes << "홈팀 B2B(연속경기) 상황" if @game.home_edge&.include?("B2B")
    schedule_notes << "원정팀 B2B(연속경기) 상황" if @game.away_edge&.include?("B2B")
    schedule_notes << @game.schedule_note if @game.schedule_note.present?
    schedule_context = schedule_notes.join(", ")

    lines_context = []
    lines_context << "스프레드: #{@game.home_spread}" if @game.home_spread.present?
    lines_context << "오버/언더: #{@game.total_line}" if @game.total_line.present?
    lines_str = lines_context.join(" | ")

    triggers = @report.triggers.join(", ")
    signals = @report.signals.join(", ")
    edge_score = @report.edge_score
    confidence = @report.confidence

    # 픽 정보는 티저만 - 실제 방향은 노출하지 않음
    pick_type_kr = case @report.pick_type
                   when "spread" then "스프레드"
                   when "total" then "오버/언더"
                   when "moneyline" then "머니라인"
                   else @report.pick_type.to_s
                   end

    <<~PROMPT
      당신은 한국어 스포츠 베팅 분석 블로그의 전문 작가입니다.
      아래 경기 정보를 바탕으로 SEO에 최적화된 한국어 블로그 포스트를 작성해주세요.

      ## 경기 정보
      - 리그: #{league}
      - 경기: #{away} #{away_record} vs #{home} #{home_record}
      - 날짜: #{game_date_str}
      - 라인: #{lines_str.presence || "정보 없음"}
      - 스케줄 컨텍스트: #{schedule_context.presence || "없음"}
      - 분석 트리거: #{triggers.presence || "없음"}
      - 분석 신호: #{signals.presence || "없음"}
      - 엣지 스코어: #{edge_score.present? ? "#{edge_score}/100" : "분석 중"}
      - 신뢰도: #{confidence.presence || "분석 중"}
      - 분석 타입: #{pick_type_kr.presence || "종합"}

      ## 작성 지침
      1. **제목(TITLE)**: SEO 친화적 제목. 팀명, 날짜, #{league} 키워드 포함. 60자 이내. 예: "#{away} vs #{home} #{game_date_str} #{league} 분석 - 스케줄 엣지와 베팅 포인트"
      2. **메타설명(META)**: 검색 스니펫용 요약. 120-155자. 클릭을 유도하는 문장.
      3. **태그(TAGS)**: SEO 키워드 5-7개, 쉼표 구분. 예: NBA,농구분석,스포츠베팅,#{away},#{home}
      4. **본문(CONTENT)**: 800-1200자 분량의 한국어 블로그 포스트
         - 서론: 경기 소개 및 주목 포인트
         - 경기 분석: 스케줄 팩터, 팀 상황, 라인 분석을 대중적 언어로 설명
         - 핵심 엣지: 이 경기에서 주목할 분석 포인트 (구체적 픽 방향은 절대 공개 금지)
         - CTA: "전문 분석과 정확한 픽은 게이트9 프리미엄 구독자에게만 제공됩니다"로 마무리
         - 자연스럽게 키워드(#{league}, #{away}, #{home}, 베팅, 분석) 포함

      ## 출력 형식 (정확히 지켜주세요)
      TITLE: [제목]
      META: [메타설명]
      TAGS: [태그1,태그2,태그3]
      CONTENT:
      [본문 내용]
    PROMPT
  end

  def call_llm(prompt)
    client = OpenrouterClient.new
    client.chat(prompt)
  rescue => e
    Rails.logger.error("[InsightGenerator] LLM call failed: #{e.message}")
    nil
  end

  def create_insight(raw_content)
    parsed = parse_llm_output(raw_content)

    title = parsed[:title].presence || fallback_title
    content = parsed[:content].presence || raw_content
    meta_description = parsed[:meta].presence
    tags = parsed[:tags].presence

    insight = Insight.create!(
      title: title,
      content: content,
      meta_description: meta_description,
      tags: tags,
      category: "team_analysis",
      sport_id: @game.sport_id,
      report_id: @report.id,
      status: "published",
      published_at: Time.current
    )

    Rails.logger.info("[InsightGenerator] Created Insight ##{insight.id} for Report ##{@report.id}: #{title}")
    insight
  end

  def parse_llm_output(raw)
    result = {}

    # TITLE: 라인 추출
    if (m = raw.match(/^TITLE:\s*(.+)$/))
      result[:title] = m[1].strip
    end

    # META: 라인 추출
    if (m = raw.match(/^META:\s*(.+)$/))
      result[:meta] = m[1].strip
    end

    # TAGS: 라인 추출
    if (m = raw.match(/^TAGS:\s*(.+)$/))
      result[:tags] = m[1].strip
    end

    # CONTENT: 이후 모든 내용 추출
    if (m = raw.match(/^CONTENT:\s*\n(.*)/m))
      result[:content] = m[1].strip
    end

    result
  end

  def fallback_title
    game_date_str = @game.game_date&.in_time_zone("Asia/Seoul")&.strftime("%Y.%m.%d") || ""
    league = @game.league_name.presence || @game.league.presence || "NBA"
    "#{@game.away_team} vs #{@game.home_team} #{game_date_str} #{league} 분석"
  end
end
