class PlanCatalog
  CATALOG_PATH = Rails.root.join("config", "plans.json")

  DEFAULT_CATALOG = {
    "plans" => [
      { "key" => "daily", "name" => "일간 패스", "duration_days" => 1, "price_krw" => 3000, "description" => "오늘 경기용 프리미엄 리포트를 바로 확인할 수 있는 단기 패스", "teaser" => "무료 공개 리포트를 본 뒤 하루 단위로 업그레이드하세요.", "featured" => false, "benefits" => ["당일 프리미엄 리포트 전체 열람", "핵심 픽 요약 카드 제공", "경기 전 체크리스트 확인"] },
      { "key" => "weekly", "name" => "주간 패스", "duration_days" => 7, "price_krw" => 15000, "description" => "한 주 동안 주요 리그 리포트와 콘텐츠 패키지를 보는 운영형 플랜", "teaser" => "연속 경기 흐름과 라인 변화를 함께 추적하는 주간 운영용", "featured" => false, "benefits" => ["7일간 프리미엄 리포트 무제한", "콘텐츠 티저 카드 우선 제공", "주간 성과 요약 확인"] },
      { "key" => "monthly", "name" => "월간 패스", "duration_days" => 30, "price_krw" => 50000, "description" => "매일 분석을 보는 핵심 사용자용 플랜", "teaser" => "가장 낮은 일 단가로 리포트와 운영 콘텐츠를 모두 활용하세요.", "featured" => true, "benefits" => ["30일간 프리미엄 리포트 전체 열람", "AdCraft 연동 콘텐츠 패키지 우선 생성", "백테스트 성과 지표와 최근 적중 기록 확인"] }
    ],
    "premium_benefits" => ["모든 프리미엄 리포트 열람", "백테스트 기반 신뢰도 분석", "5인 AI 분석가 종합 의견", "경기 전 체크리스트"]
  }.freeze

  class << self
    def ordered_plans
      @ordered_plans ||= load_catalog.fetch("plans").map { |plan| normalize_plan(plan) }
    end

    def plans_by_key
      @plans_by_key ||= ordered_plans.index_by { |plan| plan[:key] }
    end

    def premium_benefits
      @premium_benefits ||= load_catalog.fetch("premium_benefits", [])
    end

    def reset!
      @ordered_plans = nil
      @plans_by_key = nil
      @premium_benefits = nil
      @catalog = nil
    end

    private

    def load_catalog
      @catalog ||= if File.exist?(CATALOG_PATH)
        JSON.parse(File.read(CATALOG_PATH))
      else
        DEFAULT_CATALOG
      end
    end

    def normalize_plan(plan)
      duration_days = plan.fetch("duration_days").to_i

      {
        key: plan.fetch("key"),
        name: plan.fetch("name"),
        duration: duration_days.days,
        duration_days: duration_days,
        price: plan.fetch("price_krw").to_i,
        description: plan["description"],
        teaser: plan["teaser"],
        featured: plan["featured"] == true,
        benefits: Array(plan["benefits"])
      }
    end
  end
end
