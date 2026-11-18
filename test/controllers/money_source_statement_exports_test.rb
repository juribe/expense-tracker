# frozen_string_literal: true

require "test_helper"
require "csv"
require "stringio"

class MoneySourceStatementExportsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Export User", email: "statement_exports@example.com", password: "password123")
    sign_in @user
    @source = @user.money_sources.create!(name: "Cuenta Ahorros", kind: "account", starting_balance: 1_000_000)
  end

  test "CSV exports every filtered movement, not only the visible page" do
    30.times do |index|
      expense(description: "Movimiento #{index}", amount: 1_000)
    end

    get extractos_money_source_path(@source, format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/attachment/, response.headers["Content-Disposition"])

    rows = CSV.parse(response.body)
    assert_equal 31, rows.size
    assert_equal "Fecha", rows.first.first
    assert(rows.drop(1).any? { |row| row.include?("Movimiento 29") })
  end

  test "CSV respects the active search filter" do
    expense(description: "Café Central", amount: 12_000)
    expense(description: "Mercado", amount: 45_000)

    get extractos_money_source_path(@source, format: :csv, params: { q: "Café" })

    assert_response :success
    rows = CSV.parse(response.body)
    assert_equal 2, rows.size
    assert_equal "Café Central", rows.second[1]
  end

  test "CSV neutralizes descriptions that look like spreadsheet formulas" do
    expense(description: '=HYPERLINK("https://evil.example")', amount: 5_000)

    get extractos_money_source_path(@source, format: :csv)

    rows = CSV.parse(response.body)
    assert_equal '\'=HYPERLINK("https://evil.example")', rows.second[1]
  end

  test "XLSX exports a valid Excel workbook with the movements" do
    expense(description: "Mercado Central", amount: 45_000)

    get extractos_money_source_path(@source, format: :xlsx)

    assert_response :success
    assert_equal "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", response.media_type
    assert_match(/\.xlsx/, response.headers["Content-Disposition"])
    assert response.body.start_with?("PK"), "expected an XLSX zip container"
  end

  test "PDF includes the source summary on the first page and movements afterwards" do
    expense(description: "Mercado Central", amount: 45_000)

    get extractos_money_source_path(@source, format: :pdf)

    assert_response :success
    assert_equal "application/pdf", response.media_type

    reader = PDF::Reader.new(StringIO.new(response.body))
    assert_operator reader.page_count, :>=, 2

    first_page = reader.pages.first.text
    assert_match(/Cuenta Ahorros/, first_page)
    assert_match(/Resumen de la fuente/, first_page)
    assert_match(/Saldo inicial/, first_page)
    refute_match(/Mercado Central/, first_page)

    movements_text = reader.pages.drop(1).map(&:text).join("\n")
    assert_match(/Mercado Central/, movements_text)
  end

  test "exports isolate each user's money sources" do
    other = User.create!(name: "Other", email: "other_exports@example.com", password: "password123")
    other_source = other.money_sources.create!(name: "Ajena", kind: "account")

    get extractos_money_source_path(other_source, format: :csv)

    assert_response :not_found
  end

  test "movements tab renders the export links" do
    expense(description: "Mercado", amount: 45_000)

    get extractos_money_source_path(@source)

    assert_response :success
    assert_select "a[href*='.csv']"
    assert_select "a[href*='.xlsx']"
    assert_select "a[href*='.pdf']"
  end

  private

  def expense(description:, amount:)
    @user.expenses.create!(
      money_source: @source, amount: amount, date: Date.current,
      description: description, source: "manual"
    )
  end
end
