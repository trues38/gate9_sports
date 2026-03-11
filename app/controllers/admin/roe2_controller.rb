# frozen_string_literal: true

# Admin::Roe2Controller - YouTube 인사이트 → Neo4j 업로드
#
# ROE-2 파이프라인:
# 1. YouTube URL 입력
# 2. 콘텐츠 추출
# 3. AI 자동 분석 (OpenRouter) 또는 수동 입력
# 4. Neo4j 업로드
#
class Admin::Roe2Controller < Admin::BaseController
  # GET /admin/roe2
  def index
    @recent_narratives = fetch_recent_narratives
  end

  # GET /admin/roe2/new
  def new
    @teams = fetch_teams
  end

  # POST /admin/roe2/extract
  def extract
    @url = params[:url]

    begin
      @extracted = YouTubeExtractor.extract(@url)
      @suggestions = { narratives: [], tactics: [] }
      @teams = fetch_teams
      render :edit
    rescue YouTubeExtractor::ExtractionError => e
      flash[:error] = "추출 실패: #{e.message}"
      redirect_to new_admin_roe2_path
    end
  end

  # POST /admin/roe2/analyze - AI 자동 분석
  def analyze
    @url = params[:url]
    @extracted = {
      url: @url,
      title: params[:title],
      description: params[:description],
      content: params[:content],
      channel: params[:channel],
      video_id: params[:video_id]
    }
    @teams = fetch_teams

    begin
      client = OpenRouterClient.new
      @suggestions = client.analyze_insights(params[:content], team_hint: params[:team_hint])

      if @suggestions[:error]
        flash.now[:warning] = "AI 분석 실패: #{@suggestions[:error]} - 수동 입력하세요"
      elsif @suggestions[:parse_error]
        flash.now[:warning] = "AI 응답 파싱 실패 - 수동 입력하세요"
      else
        flash.now[:success] = "AI 분석 완료! #{@suggestions[:narratives].length}개 서사 + #{@suggestions[:tactics].length}개 전술 발견"
      end
    rescue StandardError => e
      @suggestions = { narratives: [], tactics: [] }
      flash.now[:error] = "AI 분석 오류: #{e.message}"
    end

    render :edit
  end

  # POST /admin/roe2
  def create
    client = Neo4jClient.new
    created_items = []

    # NarrativeContext 생성
    if params[:narrative_contexts].present?
      params[:narrative_contexts].each do |nc|
        next if nc[:description].blank?

        nc_id = client.create_narrative_context(
          type: nc[:type],
          description: nc[:description],
          team: nc[:team],
          player: nc[:player],
          source_url: params[:source_url],
          source_title: params[:source_title]
        )
        created_items << { type: "NarrativeContext", id: nc_id }
      end
    end

    # TacticalConcept 생성
    if params[:tactical_concepts].present?
      params[:tactical_concepts].each do |tc|
        next if tc[:name].blank?

        name = client.create_tactical_concept(
          name: tc[:name],
          category: tc[:category],
          description: tc[:description],
          mechanism: tc[:mechanism],
          team: tc[:team],
          player: tc[:player],
          source_url: params[:source_url]
        )
        created_items << { type: "TacticalConcept", name: name }
      end
    end

    if created_items.any?
      flash[:success] = "#{created_items.length}개 인사이트 Neo4j 업로드 완료!"
    else
      flash[:warning] = "업로드할 인사이트가 없습니다."
    end

    redirect_to admin_roe2_index_path
  rescue Neo4jClient::QueryError => e
    flash[:error] = "Neo4j 오류: #{e.message}"
    redirect_to new_admin_roe2_path
  end

  private

  def fetch_teams
    # NBA 팀 약어 목록
    %w[ATL BOS BKN CHA CHI CLE DAL DEN DET GSW HOU IND LAC LAL MEM MIA MIL MIN NOP NYK OKC ORL PHI PHX POR SAC SAS TOR UTA WAS]
  end

  def fetch_recent_narratives
    client = Neo4jClient.new
    client.query(<<~CYPHER)
      MATCH (nc:NarrativeContext)
      RETURN nc.nc_id as id, nc.type as type, nc.team as team, nc.description as description
      ORDER BY nc.extracted_at DESC
      LIMIT 10
    CYPHER
  rescue StandardError
    []
  end
end
