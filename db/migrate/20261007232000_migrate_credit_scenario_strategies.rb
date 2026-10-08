class MigrateCreditScenarioStrategies < ActiveRecord::Migration[8.0]
  # Maps the legacy scenario kinds to the Colombian application types:
  #   one_time_extra  → reduce_term (one-shot)
  #   recurring_extra → reduce_term + repeat_every (every N periods)
  def up
    CreditScenario.where(kind: "one_time_extra").find_each do |scenario|
      scenario.update!(kind: "reduce_term")
    end

    CreditScenario.where(kind: "recurring_extra").find_each do |scenario|
      params = scenario.params.merge(
        "repeat_every" => (scenario.params["every_n_periods"] || 1).to_i,
        "after_period" => (scenario.params["start_period"] || 1).to_i
      )
      params.except!("every_n_periods", "start_period")
      scenario.update!(kind: "reduce_term", params: params)
    end
  end

  def down
    CreditScenario.where(kind: "reduce_term").find_each do |scenario|
      if scenario.params["repeat_every"]
        params = scenario.params.merge(
          "every_n_periods" => scenario.params["repeat_every"].to_i,
          "start_period" => (scenario.params["after_period"] || 1).to_i
        ).except("repeat_every", "after_period")
        scenario.update!(kind: "recurring_extra", params: params)
      else
        scenario.update!(kind: "one_time_extra")
      end
    end
  end
end
