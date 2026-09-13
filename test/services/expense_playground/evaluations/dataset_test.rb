# frozen_string_literal: true

require "test_helper"
require "csv"

class ExpensePlaygroundEvaluationsDatasetTest < ActiveSupport::TestCase
  def csv_for(rows)
    CSV.generate do |csv|
      rows.each_with_index { |row, index| index.zero? ? csv << row : csv << row }
    end
  end

  def valid_dataset
    ExpensePlayground::Evaluations::Dataset.build(
      content: csv_for([
        %w[message expected_json],
        [ "me gasté 20mil hoy en almuerzo", { "intent" => "expense", "amount" => 20_000 }.to_json ]
      ]),
      filename: "gastos.csv"
    )
  end

  test "parses a valid CSV into rows with stable line numbers" do
    dataset = valid_dataset

    assert dataset.valid?
    assert_empty dataset.errors
    assert_equal 1, dataset.rows.length
    row = dataset.rows.first
    assert_equal 2, row.number
    assert_equal "me gasté 20mil hoy en almuerzo", row.message
    assert_equal({ "intent" => "expense", "amount" => 20_000 }, row.expected_json)
  end

  test "computes a sha256 checksum of the raw content for dataset versioning" do
    dataset = valid_dataset
    assert_equal 64, dataset.checksum.length
    assert_equal dataset.checksum,
                 ExpensePlayground::Evaluations::Dataset.build(
                   content: csv_for([
                     %w[message expected_json],
                     [ "me gasté 20mil hoy en almuerzo", { "intent" => "expense", "amount" => 20_000 }.to_json ]
                   ]),
                   filename: "otro.csv"
                 ).checksum
  end

  test "reports rows with empty messages as invalid and skips them" do
    dataset = ExpensePlayground::Evaluations::Dataset.build(
      content: csv_for([ %w[message expected_json], [ "", { "amount" => 1 }.to_json ] ]),
      filename: "gastos.csv"
    )

    assert_not dataset.valid?
    assert_equal 1, dataset.errors.length
    assert_match(/Row 2:/, dataset.errors.first)
    assert_empty dataset.rows
  end

  test "reports rows whose expected_json is not valid JSON" do
    dataset = ExpensePlayground::Evaluations::Dataset.build(
      content: csv_for([ %w[message expected_json], [ "una compra", "not-json{" ] ]),
      filename: "gastos.csv"
    )

    assert_not dataset.valid?
    assert_match(/Row 2:/, dataset.errors.first)
    assert_empty dataset.rows
  end

  test "requires the message and expected_json headers" do
    dataset = ExpensePlayground::Evaluations::Dataset.build(
      content: csv_for([ %w[message], [ "hola" ] ]),
      filename: "gastos.csv"
    )

    assert_not dataset.valid?
    assert_match(/Missing required column\(s\): expected_json/, dataset.errors.join(" "))
  end

  test "rejects empty files" do
    dataset = ExpensePlayground::Evaluations::Dataset.build(content: "", filename: "gastos.csv")
    assert_not dataset.valid?
    assert_match(/empty/, dataset.errors.first)
  end

  test "reports malformed CSV files" do
    dataset = ExpensePlayground::Evaluations::Dataset.build(
      content: "message,expected_json\n\"unclosed",
      filename: "gastos.csv"
    )
    assert_not dataset.valid?
    assert dataset.errors.any? { |error| error.include?("well-formed CSV") }
  end

  test "accepts base64 data URIs (browser File.text fallback)" do
    raw = csv_for([
      %w[message expected_json],
      [ "me gasté 20mil", { "intent" => "expense", "amount" => 20_000 }.to_json ]
    ])
    dataset = ExpensePlayground::Evaluations::Dataset.build(
      content: "data:text/csv;base64,#{Base64.strict_encode64(raw)}",
      filename: "gastos.csv"
    )

    assert dataset.valid?
    assert_equal 1, dataset.rows.length
  end

  test "xlsx datasets are rejected until a loader exists" do
    assert_raises(ExpensePlayground::Evaluations::Dataset::Invalid) do
      ExpensePlayground::Evaluations::Dataset.build(content: "x", filename: "gastos.xlsx")
    end
  end
end
