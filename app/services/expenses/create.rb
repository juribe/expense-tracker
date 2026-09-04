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
  #     gmail_message_id: "18f0c2..."
  #   ) => Expense (raises Expenses::Create::Invalid when unusable)
  class Create
    class Invalid < StandardError; end

    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(user:, amount:, description:, category:, occurred_at:, source:, gmail_message_id: nil, money_source: nil)
      @user = user
      @amount = amount
      @description = description
      @category = category
      @occurred_at = occurred_at
      @source = source
      @gmail_message_id = gmail_message_id
      @money_source = money_source
    end

    def call
      Expense.new(
        user: @user,
        category: resolve_category!,
        amount: parse_amount!,
        description: normalize_description,
        date: parse_date!,
        source: normalize_source!,
        gmail_message_id: @gmail_message_id.presence,
        money_source: @money_source
      ).tap(&:save!)
    end

    private

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

      if @category.is_a?(Numeric) || @category.to_s.match?(/\A\d+\z/)
        return Category.find(@category)
      end

      name = @category.to_s.strip
      raise Invalid, "category is required" if name.blank?

      Category.for_user(@user).where("lower(name) = ?", name.downcase).first ||
        Category.create!(name: name.split.map(&:capitalize).join(" "), user: @user, is_default: false)
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
