# frozen_string_literal: true

module DebtCapacity
  # Turns recorded debt facts into explainable, non-prescriptive suggestions.
  class Recommendations
    def initialize(debts:, monthly_income: nil)
      @debts = debts
      @monthly_income = monthly_income&.to_d
    end

    def call
      result = { prioritize: [], negotiate: [], keep_current: [], data_gaps: [] }
      priority_name = priority_debt_name

      @debts.each do |debt|
        if incomplete?(debt)
          result[:data_gaps] << { name: debt[:name], reason: "Faltan datos financieros para comparar esta obligación." }
        elsif urgent?(debt)
          result[:keep_current] << recommendation(debt, "Ponte al día o confirma la fecha de vencimiento antes de hacer abonos extraordinarios.")
        elsif negotiation_candidate?(debt)
          result[:negotiate] << recommendation(debt, "Consulta si es posible ajustar tasa, cuota o plazo; una cuota menor puede aumentar el costo total.")
        elsif debt[:name] == priority_name
          result[:prioritize] << recommendation(debt, "Tiene la tasa y el costo de interés más altos registrados frente a las demás obligaciones.")
        else
          result[:keep_current] << recommendation(debt, "Mantén los pagos contractuales al día mientras atiendes las obligaciones de mayor costo o presión.")
        end
      end

      result[:prioritize].sort_by! { |item| -item[:annual_rate].to_d }
      result
    end

    private

    def incomplete?(debt)
      debt[:balance].nil? || debt[:annual_rate].nil? || debt[:monthly_interest].nil?
    end

    def urgent?(debt)
      %i[overdue at_risk].include?(debt[:status].to_sym)
    end

    def negotiation_candidate?(debt)
      return false if @monthly_income.to_d.zero?

      debt[:monthly_installment].to_d / @monthly_income.to_d >= 0.30
    end

    def priority_debt_name
      candidates = @debts.reject { |debt| incomplete?(debt) || urgent?(debt) || negotiation_candidate?(debt) }
      return if candidates.one?

      candidates.max_by do |debt|
        [ debt[:annual_rate].to_d, debt[:monthly_interest].to_d, debt[:balance].to_d ]
      end&.dig(:name)
    end

    def recommendation(debt, reason)
      { name: debt[:name], reason: reason, annual_rate: debt[:annual_rate], balance: debt[:balance] }
    end
  end
end
