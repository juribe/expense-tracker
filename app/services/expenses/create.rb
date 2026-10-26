# frozen_string_literal: true

module Expenses
  # Single entry point for creating expenses from ANY source (manual, text,
  # voice, gmail, ai...). Keeps validation and category resolution consistent.
  #
  #   Expenses::Create.call(
  #     user: user,
  #     amount: 48500,
  #     description: "Restaurante XYZ",
  #     category: "restaurants",       # Category, id or name
  #     occurred_at: Time.current,
  #     source: :gmail,
  #     gmail_message_id: "18f0c2...",
  #     money_source: funding          # MoneySource — always required
  #   ) => Expense (raises Expenses::Create::Invalid when unusable)
  class Create
    class Invalid < StandardError; end

    EMAIL_SOURCES = %w[gmail cloudflare resend].freeze

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(user:, amount:, description:, category:, occurred_at:, source:, gmail_message_id: nil, money_source: nil, idempotency_key: nil)
      @user = user
      @amount = amount
      @description = description
      @category = category
      @occurred_at = occurred_at
      @source = source
      @gmail_message_id = gmail_message_id
      @money_source = money_source
      @idempotency_key = idempotency_key
    end

    def call
      raise_if_gmail_duplicate!
      raise_if_money_source_blank!

      Expense.new(
        user: @user,
        category: resolve_category!,
        amount: parse_amount!,
        description: normalize_description,
        date: parse_date!,
        source: normalize_source!,
        gmail_message_id: @gmail_message_id.presence,
        money_source: @money_source,
        idempotency_key: @idempotency_key
      ).tap(&:save!)
    end

    private

    # Expenses always leave from a known source. One exception: an active
    # rule may fill the money source at create time (rule actions set one),
    # so extraction paths holding only a text/grid input still resolve.
    def raise_if_money_source_blank!
      return if @money_source.is_a?(MoneySource)
      return if a_matching_rule_sets_the_money_source?

      raise Invalid, "money source is required"
    end

    def a_matching_rule_sets_the_money_source?
      probe = Expense.new(user: @user, amount: @amount.to_s,
                          description: normalize_description)
      TransactionRule.active.for_user(@user).ordered_by_specificity
                     .any? { |rule| rule.action_money_source_id.present? && rule.matches?(probe) }
    end

    # Database-level last line of defense (partial unique index
    # index_transactions_gmail_dedup): one imported email must never produce
    # two expenses with the same amount and date, even when import runs race.
    # The legacy gmail_message_id column stores the external email id for
    # every email source, including Cloudflare inbound mail.
    def raise_if_gmail_duplicate!
      return if @gmail_message_id.blank?

      normalized = normalize_source!
      return unless EMAIL_SOURCES.include?(normalized)

      amount = parse_amount!
      date = parse_date!

      duplicated = Expense.where(
        user_id: @user.id,
        gmail_message_id: @gmail_message_id,
        amount: amount_for_comparison(amount),
        date: date
      ).exists?
      raise Invalid, "an expense for this email, amount and date already exists" if duplicated
    end

    def amount_for_comparison(value)
      -value
    end

    # Upper bound matching the `numeric(10,2)` expenses.amount column
    # (precision 10, scale 2 => max 99,999,999.99) so a huge/garbled amount
    # fails validation instead of raising PG::NumericValueOutOfRange.
    MAX_AMOUNT = BigDecimal("99_999_999.99")

    def parse_amount!
      value = @amount.is_a?(Numeric) ? BigDecimal(@amount.to_s) : BigDecimal(@amount.to_s.gsub(/[^0-9.\-]/, ""))
      raise Invalid, "amount must be greater than zero" unless value.positive?
      raise Invalid, "amount is too large" if value > MAX_AMOUNT

      value
    rescue ArgumentError, TypeError
      raise Invalid, "amount is invalid"
    end

    def parse_date!
      return Date.current if @occurred_at.blank?

      (@occurred_at.respond_to?(:to_date) ? @occurred_at.to_date : Date.parse(@occurred_at.to_s))
    rescue ArgumentError, TypeError
      raise Invalid, "occurred_at is invalid"
    end

    def resolve_category!
      return @category if @category.is_a?(Category)

      if (category_id = UuidParams.normalize(@category))
        return Category.find(category_id)
      end

      name = @category.to_s.strip
      raise Invalid, "category is required" if name.blank?

      # ClosestResolver folds "very close" names into an existing category, so
      # creating an expense never spawns near-duplicate categories. Similarity
      # folds are recorded as rule knowledge (the reviewable mapping log).
      resolved = Categories::ClosestResolver.call(user: @user, name: name, activity: @description)
      resolved.category ||
        Category.create!(name: name.split.map(&:capitalize).join(" "), user: @user, is_default: false, category_type: "expense")
    end

    def normalize_description
      @description.to_s.strip.presence&.truncate(255)
    end

    def normalize_source!
      source = @source.to_s.downcase.strip
      raise Invalid, "source is required" if source.blank?

      source
    end
  end
end
