# frozen_string_literal: true

require "test_helper"

class ExpensePlaygroundEvaluationsResultBuilderTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "result-builder@example.com", password: "password123")
    @comida = Category.create!(name: "Comida", is_default: true, category_type: "expense")
    @almuerzos = Category.create!(user: @user, name: "Almuerzos", category_type: "expense", parent: @comida)
  end

  def candidate(overrides = {})
    ExpenseCandidate.new({
      amount: 20_000,
      currency: "COP",
      category_id: @almuerzos.id,
      category_name: "Almuerzos",
      description: "Almuerzo con clientes",
      merchant: nil,
      date: Date.new(2026, 9, 12),
      confidence: 0.98,
      money_source_id: 1,
      money_source_name: "Nequi"
    }.merge(overrides))
  end

  test "emits every required field of the FINAL result document" do
    result = ExpensePlayground::Evaluations::ResultBuilder.call(candidate: candidate)

    assert_equal true, result[:valid]
    %w[intent amount date activity category subcategory money_source currency].each do |field|
      assert result[:json].key?(field)
    end
    assert_equal "expense", result[:json]["intent"]
    assert_equal 20_000, result[:json]["amount"]
    assert_equal "2026-09-12", result[:json]["date"]
    assert_equal "Almuerzo con clientes", result[:json]["activity"]
    assert_equal "Nequi", result[:json]["money_source"]
    assert_equal "COP", result[:json]["currency"]
  end

  test "splits a two-level category tree into category and subcategory" do
    result = ExpensePlayground::Evaluations::ResultBuilder.call(candidate: candidate)

    assert_equal "Comida", result[:json]["category"]
    assert_equal "Almuerzos", result[:json]["subcategory"]
  end

  test "a root category has no subcategory" do
    result = ExpensePlayground::Evaluations::ResultBuilder.call(
      candidate: candidate(category_id: @comida.id, category_name: "Comida")
    )

    assert_equal "Comida", result[:json]["category"]
    assert_nil result[:json]["subcategory"]
  end

  test "a missing candidate is invalid" do
    result = ExpensePlayground::Evaluations::ResultBuilder.call(candidate: nil)
    assert_equal false, result[:valid]
    assert_nil result[:json]
  end
end
