# frozen_string_literal: true

require "test_helper"
require "csv"
require "pdf/reader"
require "stringio"
require "zip"

class MoneySourcesStatementExportsTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Exporter User", email: "statement_exporters@example.com", password: "password123")
    @source = @user.money_sources.create!(name: "Cuenta Ahorros", kind: "account", starting_balance: 1_000_000)
    @user.expenses.create!(money_source: @source, amount: 45_000, date: Date.current,
                           description: "Mercado Central", source: "manual")
    @user.incomes.create!(money_source: @source, amount: 500_000, date: Date.current,
                          description: "Salario", source: "manual")
  end

  test "CSV includes headers and every movement" do
    rows = CSV.parse(MoneySources::StatementExports::Csv.call(statement))

    assert_equal [ "Fecha", "Descripción", "Detalle", "Categoría", "Tipo", "Monto", "Fuente relacionada" ],
                 rows.first
    assert_equal 3, rows.size
    mercado = rows.find { |row| row[1] == "Mercado Central" }
    assert_equal Date.current.iso8601, mercado[0]
    assert_equal "Gasto", mercado[4]
    assert_equal "-45000.0", mercado[5]
  end

  test "CSV neutralizes formula-like cells" do
    @user.expenses.create!(money_source: @source, amount: 1_000, date: Date.current,
                           description: "=SUM(A1:A2)", source: "manual")

    rows = CSV.parse(MoneySources::StatementExports::Csv.call(statement))
    row = rows.find { |candidate| candidate[1].include?("SUM") }

    assert_equal "'=SUM(A1:A2)", row[1]
  end

  test "XLSX contains a Movimientos worksheet with the exported rows" do
    data = MoneySources::StatementExports::Xlsx.call(statement)
    zip = Zip::File.open_buffer(StringIO.new(data))

    assert_includes read_entry(zip, "xl/workbook.xml"), "Movimientos"
    assert_includes read_entry(zip, "xl/sharedStrings.xml"), "Mercado Central"
    assert_includes read_entry(zip, "xl/worksheets/sheet1.xml"), "<sheetData>"
  end

  test "PDF places the source summary on the first page and movements later" do
    reader = PDF::Reader.new(StringIO.new(MoneySources::StatementExports::Pdf.call(statement)))

    assert_operator reader.page_count, :>=, 2
    first_page = reader.pages.first.text
    assert_match(/Cuenta Ahorros/, first_page)
    assert_match(/Resumen de la fuente/, first_page)
    assert_match(/Saldo inicial/, first_page)
    assert_match(/Saldo final del período/, first_page)
    assert_match(/1\.000\.000/, first_page)
    refute_match(/Mercado Central/, first_page)

    assert_match(/Mercado Central/, reader.pages.drop(1).map(&:text).join("\n"))
  end

  test "PDF replaces characters unsupported by the built-in font" do
    @user.expenses.create!(money_source: @source, amount: 1_000, date: Date.current,
                           description: "Café 😀", source: "manual")

    reader = PDF::Reader.new(StringIO.new(MoneySources::StatementExports::Pdf.call(statement)))
    text = reader.pages.drop(1).map(&:text).join("\n")

    assert_match(/Café \?/, text)
  end

  test "each exporter suggests a named filename" do
    date = Date.current.iso8601

    assert_equal "extracto-cuenta-ahorros-#{date}.csv", MoneySources::StatementExports::Csv.filename(statement)
    assert_equal "extracto-cuenta-ahorros-#{date}.xlsx", MoneySources::StatementExports::Xlsx.filename(statement)
    assert_equal "extracto-cuenta-ahorros-#{date}.pdf", MoneySources::StatementExports::Pdf.filename(statement)
  end

  private

  def statement
    MoneySources::Statement.new(user: @user, source: @source, period: "current", paginate: false).call
  end

  def read_entry(zip, name)
    zip.find_entry(name).get_input_stream.read
  end
end
