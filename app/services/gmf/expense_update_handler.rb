# frozen_string_literal: true

module Gmf
  # Gmf::ExpenseUpdateHandler
  # Recalculates the affected month(s) when an expense changes its amount,
  # date or money source, then keeps the linked automatic GMF charge in sync.
  class ExpenseUpdateHandler
    def self.call(expense)
      new(expense).call
    end

    def initialize(expense)
      @expense = expense
    end

    def call
      return if @expense.source.to_s == "gmf"
      return if Gmf::BankChargeDetector.bank_charge?(@expense.description)
      return unless @expense.saved_changes.key?("amount") ||
                    @expense.saved_changes.key?("date") ||
                    @expense.saved_changes.key?("money_source_id")

      old_source = MoneySource.find_by(id: old_money_source_id)
      old_date = old_date_value

      recalculate_old_period(old_source, old_date) unless same_period?(old_source, old_date)
      recalculated = recalculate_new_period

      sync_charge(recalculated&.target_result)
    end

    private

    def old_money_source_id
      @expense.saved_change_to_money_source_id? ? @expense.money_source_id_before_last_save : @expense.money_source_id
    end

    def old_date_value
      @expense.saved_change_to_date? ? @expense.date_before_last_save : @expense.date
    end

    def recalculate_old_period(source, date)
      return if source.nil? || date.nil?

      Gmf::AccumulatorRecalculator.call(user: @expense.user, money_source: source, date: date)
    end

    def recalculate_new_period
      return nil if @expense.money_source.nil?

      Gmf::AccumulatorRecalculator.call(
        user: @expense.user,
        money_source: @expense.money_source,
        date: @expense.date,
        target: @expense
      )
    end

    def same_period?(source, date)
      return false if source.nil? || date.nil? || @expense.money_source.nil?

      effective_id(source) == effective_id(@expense.money_source) &&
        date.year == @expense.date.year &&
        date.month == @expense.date.month
    end

    def effective_id(source)
      effective = source.debit_card? && source.parent ? source.parent : source
      effective.id
    end

    def sync_charge(result)
      charge = Expense.find_by(
        user_id: @expense.user_id,
        gmf_origin_type: "Expense",
        gmf_origin_id: @expense.id
      )
      gmf_amount = result ? result.gmf_amount.to_d : 0.to_d

      if gmf_amount.positive?
        orphan(charge) if charge && !charge.gmf_estimated?
        Gmf::ChargeCreator.call(
          user: @expense.user,
          origin: @expense,
          origin_type: "Expense",
          amount: gmf_amount,
          date: @expense.date,
          money_source: @expense.money_source,
          estimated: true
        )
      elsif charge
        if charge.gmf_estimated?
          charge.destroy
        else
          orphan(charge)
        end
      end
    end

    def orphan(charge)
      charge.update!(gmf_origin_type: nil, gmf_origin_id: nil, gmf_status: "orphaned")
    end
  end
end
