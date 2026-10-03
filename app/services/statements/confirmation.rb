# frozen_string_literal: true

module Statements
  # Confirmation
  # Persists the reviewed statement import: creates the selected movements as
  # Expenses (through Expenses::Create, so validations and rules are never
  # bypassed) and, when requested, creates the payment expense from the
  # funding source and applies it to the debt via Payments::Apply. The whole
  # import is one transaction — a failed payment rolls back every expense.
  #
  #   Statements::Confirmation.call(user: user, money_source: card,
  #                                 movements: [...], payment: { "register" => "1", ... })
  class Confirmation
    def self.call(user:, money_source:, movements:, payment: {})
      new(user: user, money_source: money_source, movements: movements,
          payment: payment).call
    end

    def initialize(user:, money_source:, movements:, payment: {})
      @user = user
      @money_source = money_source
      @movements = Array(movements)
      @payment = (payment || {}).to_h.stringify_keys
    end

    def call
      outcome = {}
      ActiveRecord::Base.transaction do
        outcome[:expenses] = created_expenses
        if register_payment?
          payment = apply_payment
          outcome[:payment] = payment
          outcome[:payment_expense] = payment.expense
        end
      end
      ServiceResult.success(outcome)
    rescue RollbackWithErrors => e
      ServiceResult.error(e.errors)
    rescue Expenses::Create::Invalid => e
      ServiceResult.error([ e.message ])
    end

    private

    class RollbackWithErrors < StandardError
      attr_reader :errors

      def initialize(errors)
        super(errors.to_sentence)
        @errors = Array(errors)
      end
    end

    def created_expenses
      selected_movements.filter_map do |row|
        candidate = ExpenseCandidate.from_h(row, user: @user)
        unless candidate.valid?
          raise RollbackWithErrors, candidate.errors.full_messages
        end

        create_expense(candidate, funding: nil)
      end
    end

    def selected_movements
      @movements.select { |row| row.respond_to?(:[]) && row["selected"].to_s == "1" }
    end

    def create_expense(candidate, funding: nil)
      Expenses::Create.call(
        user: @user,
        amount: candidate.amount,
        description: candidate.description.presence || candidate.merchant.presence || candidate.category_name,
        category: candidate_category(candidate),
        occurred_at: candidate.date,
        source: "statement_file",
        money_source: funding || candidate_money_source(candidate)
      )
    end

    def register_payment?
      @payment["register"].to_s == "1" && payment_amount&.positive?
    end

    # The reviewed distribution components are the source of truth: the user
    # decides what the payment is worth by typing its breakdown, so the
    # payment expense is created for that total and the distribution always
    # sums to it. The posted amount only fills in when no component was
    # typed (e.g. a plain API caller).
    def payment_amount
      components = distribution_sum
      components.positive? ? components : parse_amount(@payment["amount"])
    end

    def distribution_sum
      %w[principal_amount interest_amount insurance_amount other_amount]
        .sum { |field| parse_amount(@payment[field]) || BigDecimal("0") }
    end

    def parse_amount(value)
      return value if value.is_a?(Numeric) || value.is_a?(BigDecimal)
      return nil if value.blank?

      BigDecimal(MoneyFormat.normalize(value))
    end

    def apply_payment
      expense = Expenses::Create.call(
        user: @user,
        amount: payment_amount,
        description: @payment["description"].presence ||
                     I18n.t("payments.description_fallback"),
        category: @payment["category_id"].presence || I18n.t("statement_imports.payment_category"),
        occurred_at: @payment["date"],
        source: "statement_file",
        money_source: funding_source
      )

      result = Payments::Apply.call(user: @user, money_source: @money_source,
                                    expense: expense, distribution: @payment)
      raise RollbackWithErrors, result.errors unless result.success?

      result.result
    end

    def funding_source
      id = @payment["funding_money_source_id"].presence
      @user.money_sources.find_by(id: id) if id
    end

    def candidate_category(candidate)
      if candidate.category_id.present?
        Category.for_user(@user).find_by!(id: candidate.category_id)
      else
        candidate.category_name
      end
    end

    def candidate_money_source(candidate)
      return @money_source if candidate.money_source_id.blank?

      @user.money_sources.find(candidate.money_source_id)
    end
  end
end
