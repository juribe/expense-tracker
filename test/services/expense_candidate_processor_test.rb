# frozen_string_literal: true

require "test_helper"

class ExpenseCandidateProcessorTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Candidate User", email: "candidate@example.com", password: "password123")
    @transporte = Category.create!(name: "Transporte", category_type: "expense", user: @user)
  end

  def build(expense, categories: nil)
    ExpenseCandidateProcessor.call(expense: expense, user: @user, categories: categories)
  end

  test "builds a valid candidate from an AI expense" do
    candidate = build({
      "original_text" => "Pagué 50 mil de gasolina", "amount" => 50_000,
      "date" => "2026-09-16", "description" => "gasolina", "category" => "Transporte",
      "money_source_hint" => "la clásica"
    })

    assert candidate.valid?
    assert_equal 50_000, candidate.amount
    assert_equal Date.new(2026, 9, 16), candidate.date
    assert_equal "gasolina", candidate.description
    assert_equal @transporte.id, candidate.category_id
    assert_equal "Transporte", candidate.category_name
    assert_equal "la clásica", candidate.money_source_name
    assert_equal "ai", candidate.classification_source
    assert_equal "COP", candidate.currency
    assert_equal "playground", candidate.source
  end

  test "keeps the category as a suggestion when it does not match the user's categories" do
    candidate = build({
      "original_text" => "gasté 20 mil en un antojo", "amount" => 20_000,
      "date" => "2026-09-16", "description" => "antojo", "category" => "Antojos",
      "money_source_hint" => nil
    })

    assert_nil candidate.category_id
    assert_equal "Antojos", candidate.category_name
    assert_equal "Antojos", candidate.suggested_category_name
  end

  test "resolves the category from the explicitly passed set" do
    candidate = build({
      "original_text" => "pagué 30 mil en transporte", "amount" => 30_000,
      "date" => "2026-09-16", "description" => "transporte", "category" => "Transporte",
      "money_source_hint" => nil
    }, categories: [ @transporte ])

    assert_equal @transporte.id, candidate.category_id
    assert_equal "Transporte", candidate.category_name
    assert_nil candidate.suggested_category_name
  end

  test "resolves a category passed as a name string against the user's categories" do
    candidate = build({
      "original_text" => "pagué 30 mil en transporte", "amount" => 30_000,
      "date" => "2026-09-16", "description" => "transporte", "category" => "Transporte",
      "money_source_hint" => nil
    }, categories: [ "Comida", "Transporte" ])

    assert_equal @transporte.id, candidate.category_id
    assert_equal "Transporte", candidate.category_name
  end

  test "keeps a suggestion when the explicitly passed set does not authorize the category" do
    candidate = build({
      "original_text" => "pagué 30 mil en transporte", "amount" => 30_000,
      "date" => "2026-09-16", "description" => "transporte", "category" => "Transporte",
      "money_source_hint" => nil
    }, categories: [ "Comida" ])

    assert_nil candidate.category_id
    assert_equal "Transporte", candidate.category_name
    assert_equal "Transporte", candidate.suggested_category_name
  end

  test "falls back to original_text when description is missing" do
    candidate = build({
      "original_text" => "gasté 20 mil en gasolina", "amount" => 20_000,
      "date" => "2026-09-16", "description" => "", "category" => "Transporte",
      "money_source_hint" => nil
    })

    assert_equal "gasté 20 mil en gasolina", candidate.description
  end

  test "normalizes string amounts to integer COP values" do
    candidate = build({
      "original_text" => "50.000 en almuerzo", "amount" => "50.000",
      "date" => "2026-09-16", "description" => "almuerzo", "category" => "Otros",
      "money_source_hint" => nil
    })

    assert_equal 50_000, candidate.amount
  end

  test "invalid amount makes the candidate invalid" do
    candidate = build({
      "original_text" => "algo raro", "amount" => "no sé",
      "date" => "2026-09-16", "description" => "raro", "category" => "Otros",
      "money_source_hint" => nil
    })

    refute candidate.valid?
    assert candidate.errors.any? { |message| message.match?(/Amount/) }
  end

  test "invalid or missing date makes the candidate invalid" do
    missing_date = build({
      "original_text" => "raro", "amount" => 10_000,
      "date" => nil, "description" => "raro", "category" => "Otros",
      "money_source_hint" => nil
    })
    bad_date = build({
      "original_text" => "raro", "amount" => 10_000,
      "date" => "no es una fecha", "description" => "raro", "category" => "Otros",
      "money_source_hint" => nil
    })

    refute missing_date.valid?
    assert missing_date.errors.any? { |message| message.match?(/Date/) }
    refute bad_date.valid?
    assert bad_date.errors.any? { |message| message.match?(/Date/) }
  end
end
