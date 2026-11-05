# frozen_string_literal: true

require "test_helper"

class SavingsOpportunityAnalysisTaskTest < ActiveSupport::TestCase
  def task
    @task ||= Ai::Tasks::SavingsOpportunityAnalysis.new
  end

  def input
    {
      "period" => "Últimos 3 meses",
      "categories" => [
        { "reference" => "category:food", "name" => "Restaurantes", "current" => "900000",
          "monthly_average" => "600000", "variation_pct" => 50.0, "share_pct" => 60.0,
          "suggested_reduction_pct" => 10 }
      ],
      "recurring" => [
        { "reference" => "recurring:netflix", "name" => "Netflix", "frequency" => "monthly",
          "monthly_amount" => "29900", "confidence" => "confirmed" }
      ],
      "small_expenses" => {
        "total" => "166000", "count" => 22,
        "groups" => [ { "reference" => "small:cafe", "name" => "Café", "count" => 12, "average" => "8000" } ]
      }
    }
  end

  def context
    {
      allowed_references: [ "category:food", "recurring:netflix", "small:cafe" ]
    }
  end

  test "builds a system and user message with the aggregated context" do
    messages = task.messages(input, context)

    assert_equal "system", messages.first[:role]
    assert_includes messages.first[:content], "No inventes cifras"
    assert_includes messages.first[:content], "category:food"
    assert_equal "user", messages.last[:role]
    assert_includes messages.last[:content], "Netflix"
  end

  test "parses a valid structured response" do
    content = {
      "summary" => "Tus gastos en restaurantes han aumentado.",
      "highlights" => [
        { "reference" => "category:food", "explanation" => "Subió frente a tu promedio.",
          "recommendation" => "Revisa la frecuencia de tus pedidos." }
      ]
    }.to_json

    parsed = task.parse(content, input, context)

    assert_equal "Tus gastos en restaurantes han aumentado.", parsed[:data]["summary"]
    assert_equal "category:food", parsed[:data]["highlights"].first["reference"]
  end

  test "drops references the backend did not compute" do
    content = {
      "summary" => "Resumen.",
      "highlights" => [
        { "reference" => "category:invented", "explanation" => "x", "recommendation" => "y" },
        { "reference" => "category:food", "explanation" => "x", "recommendation" => "y" }
      ]
    }.to_json

    parsed = task.parse(content, input, context)

    assert_equal [ "category:food" ], parsed[:data]["highlights"].map { |row| row["reference"] }
  end

  test "rejects generated numeric figures" do
    content = { "summary" => "Podrías ahorrar 85000 al mes.", "highlights" => [] }.to_json

    assert_raises(Ai::Tasks::Base::InvalidResponse) do
      task.parse(content, input, context)
    end
  end

  test "drops highlights that mention figures" do
    content = {
      "summary" => "Resumen sin cifras.",
      "highlights" => [
        { "reference" => "category:food", "explanation" => "Podrías liberar 85000.", "recommendation" => "Revisa." },
        { "reference" => "recurring:netflix", "explanation" => "Se repite.", "recommendation" => "Revisa." }
      ]
    }.to_json

    parsed = task.parse(content, input, context)

    assert_equal [ "recurring:netflix" ], parsed[:data]["highlights"].map { |row| row["reference"] }
  end

  test "rejects a response without a summary" do
    assert_raises(Ai::Tasks::Base::InvalidResponse) do
      task.parse({ "highlights" => [] }.to_json, input, context)
    end
  end

  test "rejects malformed JSON" do
    assert_raises(Ai::Tasks::Base::InvalidResponse) do
      task.parse("not json", input, context)
    end
  end
end
