# frozen_string_literal: true

require "csv"

module Expenses
  # Persists several confirmed AI-entry expenses in a single transaction.
  # Any row failure aborts and rolls back the whole batch, mirroring the
  # controller's previous behavior.
  #
  #   result = Expenses::BulkCreate.call(user: user, inputs: [hash, ...])
  #   result.success?        # false when the batch failed
  #   result.created_count   # expenses persisted (0 on failure)
  #   result.error_message   # localized reason for the failure
  class BulkCreate
    def self.call(user:, inputs:)
      new(user: user, inputs: inputs).call
    end

    attr_reader :created_count, :error_message, :expenses

    def initialize(user:, inputs:)
      @user = user
      @inputs = normalize_inputs(inputs)
      @created_count = 0
      @error_message = nil
      @expenses = []
    end

    def call
      return fail(I18n.t("expenses.no_expenses_to_save")) if @inputs.empty?

      ActiveRecord::Base.transaction do
        @inputs.each_with_index do |input, index|
          begin
            expense = build_expense(input)
            unless expense.save
              raise ActiveRecord::RecordInvalid, row_error(expense, index)
            end
          rescue ArgumentError => e
            raise ArgumentError, I18n.t("expenses.bulk_row_error", index: index + 1, message: e.message)
          end
          @expenses << expense
          @created_count += 1
        end
      end

      self
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      @created_count = 0
      @expenses = []
      fail(e.message)
    end

    def success?
      @error_message.nil?
    end

    def failure?
      !success?
    end

    private

    attr_reader :user

    def normalize_inputs(inputs)
      raw = inputs
      raw = raw.values if raw.is_a?(ActionController::Parameters)
      Array(raw).filter_map do |input|
        next if input.blank?

        source = input.respond_to?(:to_unsafe_h) ? input.to_unsafe_h : input
        ActionController::Parameters.new(source).permit(
          :amount, :description, :date, :transaction_date, :category_id, :new_category_name,
          :category_edited, :confidence, :money_source_id
        ).to_h
      end
    end

    def build_expense(input)
      amount = money_value(input[:amount])
      raise ArgumentError, "Amount is required." if amount.nil?
      raise ArgumentError, "Amount must be greater than zero." unless amount.positive?

      date = parse_confirmed_date(input[:transaction_date].presence || input[:date])

      money_source = input[:money_source_id].present? ? user.money_sources.find(input[:money_source_id]) : nil

      expense = Expense.new(
        user: user,
        category: resolve_confirmed_category!(input, amount),
        amount: amount,
        description: input[:description].to_s.presence,
        date: date,
        source: "ai",
        money_source: money_source
      )
      expense.category_locked_by_user = input[:category_edited].present?
      expense
    end

    def parse_confirmed_date(value)
      return Date.current if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      raise ArgumentError, I18n.t("expenses.invalid_date")
    end

    def resolve_confirmed_category!(input, amount)
      category_id = input[:category_id]
      new_name = input[:new_category_name].to_s.strip

      if category_id.present?
        Category.find(category_id)
      elsif new_name.present?
        # Fold "very close" names into an existing category before ever creating
        # a near-duplicate; similarity folds are recorded as rule knowledge.
        existing = Categories::ClosestResolver.call(
          user: user,
          name: new_name,
          activity: input[:description]
        ).category
        return existing if existing
        return nil if rule_will_set_category?(input, amount)

        Category.create!(name: new_name, user: user, is_default: false, category_type: "expense")
      else
        raise ArgumentError, I18n.t("expenses.category_required")
      end
    end

    # The suggested category name comes from the parser's guess. When a rule
    # matches the detected description, the rule's category wins and the
    # suggested one must not be created.
    def rule_will_set_category?(input, amount)
      probe = Expense.new(user: user, amount: amount.to_d,
                          description: input[:description].to_s.presence)
      TransactionRules::Applicator.new(user).matching_category_rule(probe).present?
    end

    def row_error(expense, index)
      details = expense.errors.full_messages.join(", ")
      I18n.t("expenses.bulk_row_error", index: index + 1,
            message: details.presence || I18n.t("expenses.could_not_be_saved"))
    end

    def money_value(value)
      return nil if value.blank?

      BigDecimal(value.to_s.delete(","))
    rescue ArgumentError, TypeError
      nil
    end

    def fail(message)
      @error_message = message
      self
    end
  end
end
