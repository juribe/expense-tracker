class FormatSavedScenarioNames < ActiveRecord::Migration[8.0]
  # Scenarios saved before money formatting existed carry raw amounts in
  # their names ("+5000000.0 para pagar menos cada mes"). Only machine
  # generated names are rewritten; user-named scenarios stay untouched.
  def up
    CreditScenario.find_each do |scenario|
      amount = scenario.params["amount"].presence
      next if amount.blank?

      formatted = MoneyFormat.currency(BigDecimal(MoneyFormat.normalize(amount)))
      base = case scenario.kind
             when "reduce_term" then "+#{formatted} para terminar antes"
             when "reduce_installment" then "+#{formatted} para pagar menos cada mes"
             when "prepay_installments" then "+#{formatted} adelantando cuotas"
             when "target_payoff" then "Terminar #{scenario.params['months_earlier'].to_i} cuotas antes"
             end
      next if base.nil? || base == scenario.name
      next unless scenario.name.match?(/\A\+[\d.,]+\s/)

      scenario.update!(name: base)
    end
  end

  def down
    # No-op: names are display-only.
  end
end
