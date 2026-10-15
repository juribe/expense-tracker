# frozen_string_literal: true

module Statements
  # Confirmation
  # Persists the reviewed statement import: creates the selected movements as
  # Expenses (through Expenses::Create, so validations and rules are never
  # bypassed) and, when requested, creates the payment expense from the funding
  # source applying it to the debt via Payments::Apply. The whole import is one
  # transaction — a failed payment rolls back every expense.
  #
  # Every selected movement must resolve to an existing category (a posted
  # category_id that belongs to the user, or a safe ClosestResolver match on the
  # parsed name); otherwise the whole batch is rejected, so an import never
  # force-classifies or silently drops a row.
  #
  # Selected movements are re-checked against the user's current expenses (and
  # against each other) right before creating anything, so a stale review can
  # never create the same financial event twice.
  #
  #   Statements::Confirmation.call(user: user, money_source: card,
  #                                 movements: [...], payment: { "register" => "1", ... })
  class Confirmation
  # ClosestResolver matches that may create an expense directly: they are
  # deterministic and always land on an existing category. A :similar fold
  # or no match at all is NOT safe — Category.create! is never called from an
  # import and the row is rejected instead.
  SAFE_MATCHES = %i[exact learned alias parking housing].freeze

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
        outcome[:skipped_duplicates] = skipped_duplicates
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

    attr_reader :skipped_duplicates

    class RollbackWithErrors < StandardError
      attr_reader :errors

      def initialize(errors)
        super(errors.to_sentence)
        @errors = Array(errors)
      end
    end

    def created_expenses
      candidates = selected_movements.map { |row| configured_candidate(row) }

      candidates.each do |candidate|
        raise RollbackWithErrors, candidate.errors.full_messages unless candidate.valid?
      end

      ExpensePlayground::DuplicateDetector.new(user: @user).flag(candidates)

      @skipped_duplicates = 0

      candidates.filter_map do |candidate|
        if candidate.duplicate
          @skipped_duplicates += 1
          next
        end

        category = safe_category_for(candidate)
        if category.nil?
          raise RollbackWithErrors, [ I18n.t("statement_imports.movement_category_required") ]
        end

        create_expense(candidate, category)
      end
    end

    def selected_movements
      @movements.select { |row| row.respond_to?(:[]) && row["selected"].to_s == "1" }
    end

    def configured_candidate(row)
      ExpenseCandidate.from_h(row, user: @user)
    end

    # A movement may only be created with a category that already exists: a
    # posted category_id wins when it belongs to the user; otherwise the parsed
    # name must resolve through one of the deterministic ClosestResolver
    # matches. Anything else is rejected — an import never invents a category.
    def safe_category_for(candidate)
      if candidate.category_id.present?
        category = Category.for_user(@user).find_by(id: candidate.category_id)
        return category if category
      end

      resolved = Categories::ClosestResolver.call(
        user: @user, name: candidate.category_name, activity: candidate.description
      )
      resolved.category if resolved.matched_by.in?(SAFE_MATCHES)
    end

    def create_expense(candidate, category)
      Expenses::Create.call(
        user: @user,
        amount: candidate.amount,
        description: candidate.description.presence || candidate.merchant.presence || candidate.category_name,
        category: category,
        occurred_at: candidate.date,
        source: "statement_file",
        money_source: candidate_money_source(candidate)
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
        category: payment_category!,
        occurred_at: @payment["date"],
        source: "statement_file",
        money_source: funding_source
      )

      result = Payments::Apply.call(user: @user, money_source: @money_source,
                                    expense: expense, distribution: @payment)
      raise RollbackWithErrors, result.errors unless result.success?

      result.result
    end

    # The payment expense must also never invent categories: only a concrete
    # category of this user qualifies.
    def payment_category!
      id = @payment["category_id"].presence
      category = id && Category.for_user(@user).find_by(id: id)
      return category if category

      raise RollbackWithErrors, [ I18n.t("statement_imports.payment_category_required") ]
    end

    def funding_source
      id = @payment["funding_money_source_id"].presence
      return nil if id.nil?

      source = @user.money_sources.find_by(id: id)
      return nil if source.nil?

      unless source.active? && source.payment_source? && source.id != @money_source.id
        raise RollbackWithErrors, [ I18n.t("statement_imports.payment_funding_invalid") ]
      end

      source
    end

    def candidate_money_source(candidate)
      return @money_source if candidate.money_source_id.blank?

      @user.money_sources.find(candidate.money_source_id)
    end
  end
end
