# frozen_string_literal: true

require "test_helper"
require "zip"

class FileImportReadersLimitsTest < ActiveSupport::TestCase
  def call_reader(reader, binary)
    reader.call(binary: binary, errors: [], warnings: [])
  end

  test "xlsx rejects an entry that expands beyond the limit" do
    buffer = Zip::OutputStream.write_buffer(StringIO.new) do |zip|
      zip.put_next_entry("xl/worksheets/sheet1.xml")
      zip.write("<sheet><v>#{'1' * 5_000}</v></sheet>")
    end

    with_env("XLSX_MAX_ENTRY_BYTES" => "1024") do
      extraction = call_reader(Expenses::FileImport::Readers::Xlsx, buffer.string)

      assert_nil extraction.text
      assert_empty extraction.rows
    end
  end

  test "csv caps the number of data rows" do
    rows = (1..205).map { |index| "2026-01-01,row #{index},#{index}" }.join("\n")
    binary = "date,description,amount\n#{rows}"

    extraction = call_reader(Expenses::FileImport::Readers::Csv, binary)

    assert_equal 200, extraction.rows.size
  end

  test "pdf reads only the allowed number of pages" do
    fake = Object.new
    def fake.page_count = 500
    def fake.page(number) = Struct.new(:text).new("page-#{number}")

    stub_method(PDF::Reader, :new, fake) do
      extraction = call_reader(Expenses::FileImport::Readers::Pdf, "%PDF-1.4")

      assert_equal 15, extraction.text.scan(/page-/).size
    end
  end
end
