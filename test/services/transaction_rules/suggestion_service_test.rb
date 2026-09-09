# frozen_string_literal: true

require "test_helper"

module TransactionRules
  class SuggestionServiceTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Test User", email: "suggestion_service@example.com", password: "password123")
      @fitness = Category.create!(name: "Fitness", is_default: true, category_type: "expense")
      @transport = Category.create!(name: "Transportation", is_default: true, category_type: "expense")
      @entertainment = Category.create!(name: "Entertainment", is_default: true, category_type: "expense")
    end

    def create_expense(description:, category:)
      Expense.create!(user: @user, category: category, amount: 50_000, date: Date.current, description: description)
    end

    test "detects a pattern when a merchant text shares >= 90% of a category with >= 5 transactions" do
      9.times { create_expense(description: "smartfit bogotá", category: @fitness) }
      create_expense(description: "smartfit bogotá", category: @transport)

      suggestions = SuggestionService.new(@user).suggestions
      pattern = suggestions.find { |s| s[:kind] == :pattern }
      refute_nil pattern
      assert_equal "smartfit bogotá", pattern[:merchant]
      assert_equal @fitness, pattern[:category]
      assert_equal 10, pattern[:count]
    end

    test "does not suggest when the merchant appears in fewer than 5 transactions" do
      4.times do |i|
        create_expense(description: "uber", category: i.even? ? @transport : @fitness)
      end
      refute(SuggestionService.new(@user).suggestions.any? { |s| s[:merchant] == "uber" })
    end

    test "suggests corrections when a merchant was corrected to the same category repeatedly" do
      5.times { create_expense(description: "netflix", category: @entertainment) }

      suggestions = SuggestionService.new(@user).suggestions
      assert suggestions.any? { |s| s[:kind] == :correction && s[:merchant] == "netflix" }
    end

    test "returns no suggestions for distinct merchants" do
      %w[alpha beta gamma].each do |name|
        create_expense(description: name, category: @fitness)
      end
      assert_empty SuggestionService.new(@user).suggestions
    end

    test "hides a pattern when a rule already covers the merchant" do
      9.times { create_expense(description: "smartfit bogotá", category: @fitness) }
      TransactionRule.create!(user: @user, merchant_contains: "smartfit", category_id: @fitness.id)

      refute(SuggestionService.new(@user).suggestions.any? { |s| s[:merchant] == "smartfit bogotá" })
    end

    test "hides a suggestion matching an existing rule regardless of case" do
      5.times { create_expense(description: "netflix", category: @entertainment) }
      TransactionRule.create!(user: @user, merchant_contains: "NETFLIX", category_id: @entertainment.id)

      assert_empty SuggestionService.new(@user).suggestions
    end

    test "hides suggestions the user dismissed" do
      5.times { create_expense(description: "netflix", category: @entertainment) }
      @user.update!(dismissed_rule_suggestions: [ "netflix" ])

      refute(SuggestionService.new(@user).suggestions.any? { |s| s[:merchant] == "netflix" })
    end

    test "keeps a suggestion visible when only its category already has a rule" do
      9.times { create_expense(description: "smartfit bogotá", category: @fitness) }
      TransactionRule.create!(user: @user, merchant_contains: "otro", category_id: @fitness.id)

      suggestions = SuggestionService.new(@user).suggestions
      assert suggestions.any? { |s| s[:merchant] == "smartfit bogotá" }
    end
  end
end