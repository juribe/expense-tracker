# frozen_string_literal: true

require "test_helper"

class ImportPipelineTest < ActiveSupport::TestCase
  FakeExtractor = Struct.new(:result) do
    def call(text:, today: Date.current)
      @called_with = text
      result
    end

    attr_reader :called_with
  end

  setup do
    @user = User.create!(name: "Test User", email: "import_pipeline_test@example.com", password: "password123")
  end

  def uploaded_file(content, name)
    @temp_files ||= []
    file = Tempfile.new(File.basename(name))
    @temp_files << file
    file.binmode
    file.write(content)
    file.rewind
    ActionDispatch::Http::UploadedFile.new(tempfile: file, filename: name)
  end

  teardown do
    @temp_files&.each { |file| file.close! }
  end

  def successful_extractor(data = nil)
    data ||= { sources: [ { kind: "account", name: "Savings", bank: "Bancolombia", balance: "5420000" } ],
               transactions: [ { date: "2026-08-01", description: "Market", amount: "-10000", type: "expense" } ] }
    FakeExtractor.new({ ok?: true, data: data, error: nil })
  end

  test "rejects a missing file" do
    result = ImportPipeline.new(user: @user, extractor: successful_extractor).call(file: nil)
    assert_not result.ok?
    assert_equal I18n.t("wizard.upload.no_file"), result.error
  end

  test "rejects an unsupported file type" do
    result = ImportPipeline.new(user: @user, extractor: successful_extractor)
                           .call(file: uploaded_file("1234", "statement.txt"))
    assert_not result.ok?
    assert_equal I18n.t("wizard.upload.unsupported_type"), result.error
  end

  test "rejects an empty file" do
    result = ImportPipeline.new(user: @user, extractor: successful_extractor)
                           .call(file: uploaded_file("", "statement.csv"))
    assert_not result.ok?
    assert_equal I18n.t("wizard.upload.empty_file"), result.error
  end

  test "extracts sources and transactions from a csv" do
    csv = "fecha,descripcion,valor\n2026-08-01,Mercado,50000\n"
    extractor = successful_extractor
    result = ImportPipeline.new(user: @user, extractor: extractor).call(file: uploaded_file(csv, "statement.csv"))

    assert result.ok?
    assert_equal [ "Savings" ], result.sources.map(&:name)
    assert_equal BigDecimal("5420000"), result.sources.first.balance
    assert_equal 1, result.transactions.length
    assert_equal "Market", result.transactions.first[:description]
    assert_equal csv, extractor.called_with
  end

  test "propagates an extraction failure" do
    extractor = FakeExtractor.new({ ok?: false, data: nil, error: "AI extraction is not configured (missing MISTRAL_API_KEY)." })
    result = ImportPipeline.new(user: @user, extractor: extractor).call(file: uploaded_file("a,b\n1,2\n", "st.csv"))
    assert_not result.ok?
    assert_equal "AI extraction is not configured (missing MISTRAL_API_KEY).", result.error
  end

  test "never creates records" do
    before = [ MoneySource.count, Transaction.count ]
    ImportPipeline.new(user: @user, extractor: successful_extractor).call(file: uploaded_file("a,b\n1,2\n", "st.csv"))
    assert_equal before, [ MoneySource.count, Transaction.count ]
  end
end
