class PlanCatalog
  CATALOG_PATH = Rails.root.join("..", "shared", "plans.json")

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
      @catalog ||= JSON.parse(File.read(CATALOG_PATH))
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
