# frozen_string_literal: true

require "test_helper"

module ExpensePlayground
  class FileProcessorTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "File Processor User", email: "file-processor@example.com", password: "password123")
    end

    # Minimal but structurally valid PDF whose /Encrypt entry makes pdf-reader
    # treat the document as password protected from the start.
    def encrypted_pdf_data_uri
      objs = {}
      objs[1] = "<< /Type /Catalog /Pages 2 0 R >>"
      objs[2] = "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
      objs[3] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>"
      objs[4] = "<< /Length 55 >>\nstream\nBT /F1 24 Tf 100 700 Td (DIDI FOOD 45000) Tj ET\nendstream"
      objs[5] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
      objs[6] = "<< /Filter /Standard /V 1 /R 2 /O <00000000000000000000000000000000> /U <00000000000000000000000000000000> /P -44 >>"

      out = +"%PDF-1.4\n"
      offsets = { 0 => 0 }
      (1..6).each do |i|
        offsets[i] = out.length
        out << "#{i} 0 obj\n#{objs[i]}\nendobj\n"
      end
      xref_pos = out.length
      out << "xref\n0 #{offsets.size}\n"
      offsets.each_value { |off| out << format("%010d 00000 n \n", off) }
      out << "trailer\n<< /Size #{offsets.size} /Root 1 0 R /Encrypt 6 0 R >>\nstartxref\n#{xref_pos}\n%%EOF\n"

      "data:application/pdf;base64,#{Base64.strict_encode64(out)}"
    end

    # Minimal but structurally valid plain PDF whose page text just needs to be
    # non-blank; the AI extraction is stubbed in the tests that use it.
    def plain_pdf_data_uri
      stream = "BT /F1 24 Tf 100 700 Td (DIDI FOOD 45000) Tj ET"
      objs = {}
      objs[1] = "<< /Type /Catalog /Pages 2 0 R >>"
      objs[2] = "<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
      objs[3] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>"
      objs[4] = "<< /Length #{stream.length} >>\nstream\n#{stream}\nendstream"
      objs[5] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

      out = +"%PDF-1.4\n"
      offsets = { 0 => 0 }
      (1..5).each do |i|
        offsets[i] = out.length
        out << "#{i} 0 obj\n#{objs[i]}\nendobj\n"
      end
      xref_pos = out.length
      out << "xref\n0 #{offsets.size}\n"
      offsets.each_value { |off| out << format("%010d 00000 n \n", off) }
      out << "trailer\n<< /Size #{offsets.size} /Root 1 0 R >>\nstartxref\n#{xref_pos}\n%%EOF\n"

      "data:application/pdf;base64,#{Base64.strict_encode64(out)}"
    end

    def stub_pdf_extraction(sources:, transactions:)
      fake_extractor = Class.new do
        define_method(:call) { |text:, today: nil| { ok?: true, data: { sources: sources, transactions: transactions }, error: nil } }
      end.new

      stub_method(Ai::StatementExtractor, :new, ->(*) { fake_extractor }) { yield }
    end

    test "assigns the statement source to every candidate when its account number matches a money source" do
      source = MoneySource.create!(user: @user, name: "Cuenta Davibank", kind: "account",
                                   bank: "Davibank", identifier: "4212097273", starting_balance: 0)

      stub_pdf_extraction(
        sources: [ { kind: "account", name: "Cuenta de Ahorros", bank: "Davibank", identifier: "7273", card_last_four: "7273" } ],
        transactions: [
          { date: "2026-08-03", description: "COMPRA POS FARMATODO VIVA", amount: 14_950, type: "expense", category: "retail", confidence: 0.9 },
          { date: "2026-08-03", description: "COMPRA POS OXXO RIO ALTO", amount: 9_000, type: "expense", category: "retail", confidence: 0.9 }
        ]
      ) do
        result = FileProcessor.call(user: @user, file_data: plain_pdf_data_uri, filename: "stmt.pdf")

        assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
        assert_equal 2, result.candidates.size
        assert result.candidates.all? { |c| c.money_source_id == source.id }
        assert result.candidates.all? { |c| c.money_source_name == "Cuenta Davibank" }
        assert result.candidates.all? { |c| c.money_source_source == "statement" }
      end
    end

    test "keyword detection on a transaction description wins over the statement source" do
      account = MoneySource.create!(user: @user, name: "Cuenta Davibank", kind: "account",
                                    bank: "Davibank", identifier: "7273", starting_balance: 0)
      wallet = MoneySource.create!(user: @user, name: "Nequi", kind: "wallet", starting_balance: 100_000)

      stub_pdf_extraction(
        sources: [ { kind: "account", name: "Cuenta de Ahorros", bank: "Davibank", identifier: "7273", card_last_four: "7273" } ],
        transactions: [
          { date: "2026-08-03", description: "Retiro desde nequi", amount: 50_000, type: "expense", category: "retail", confidence: 0.9 },
          { date: "2026-08-03", description: "COMPRA POS OXXO", amount: 9_000, type: "expense", category: "retail", confidence: 0.9 }
        ]
      ) do
        result = FileProcessor.call(user: @user, file_data: plain_pdf_data_uri, filename: "stmt.pdf")

        assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
        nequi_row = result.candidates.find { |c| c.description.include?("nequi") }
        assert_equal wallet.id, nequi_row.money_source_id
        assert_equal "detected", nequi_row.money_source_source
        oxxo_row = result.candidates.find { |c| c.description.include?("OXXO") }
        assert_equal account.id, oxxo_row.money_source_id
        assert_equal "statement", oxxo_row.money_source_source
      end
    end

    test "symbol-keyed transactions from the AI extractor produce candidates" do
      stub_pdf_extraction(
        sources: [ { kind: "account", name: "Cuenta de Ahorros", bank: "Davibank", identifier: "7273" } ],
        transactions: [
          { date: "2026-08-03", description: "COMPRA POS FARMATODO VIVA", amount: 14_950, type: "expense", category: "retail", confidence: 0.9 }
        ]
      ) do
        result = FileProcessor.call(user: @user, file_data: plain_pdf_data_uri, filename: "stmt.pdf")

        assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
        assert_equal 1, result.candidates.size
        assert_equal "COMPRA POS FARMATODO VIVA", result.candidates.first.description
        assert_equal BigDecimal("14950"), result.candidates.first.amount
      end
    end

    test "deterministic CSV fallback activities are batch classified once by AI" do
      Category.create!(name: "Compras", is_default: true, category_type: "expense")
      csv = "Fecha,Descripcion,Valor\n2026-08-03,COMPRA POS OXXO RIO ALTO,-9000\n2026-08-04,COMPRA POS OXXO RIO ALTO,-9500\n"
      file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

      calls = 0
      fake_classifier = Class.new do
        define_method(:call) { |activities:, categories:, **|
          calls += 1
          { ok?: true, data: { "compra pos oxxo rio alto" => "Compras" }, error: nil }
        }
      end.new

      stub_method(Ai::CategoryClassifier, :new, ->(*) { fake_classifier }) do
        result = FileProcessor.call(user: @user, file_data: file_data, filename: "movs.csv")

        assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
        assert_equal 2, result.candidates.size
        assert_equal 1, calls, "expected the AI classification to run once for the whole batch"
        assert result.candidates.all? { |c| c.category_name == "Compras" }
        assert result.candidates.all? { |c| c.classification_source == "ai" }
      end
    end

    test "AI classification skips activities covered by stored knowledge" do
      category = Category.create!(name: "Compras", is_default: true, category_type: "expense")
      ActivityClassification.record!(user: @user, name: "COMPRA POS OXXO RIO ALTO", category: category, source: "user")
      csv = "Fecha,Descripcion,Valor\n2026-08-03,COMPRA POS OXXO RIO ALTO,-9000\n"
      csv += "2026-08-04,COMPRA POS DESCONOCIDO,-9000\n"
      file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

      classified_activities = nil
      fake_classifier = Class.new do
        define_method(:call) { |activities:, categories:, **|
          classified_activities = activities
          { ok?: true, data: {}, error: nil }
        }
      end.new

      stub_method(Ai::CategoryClassifier, :new, ->(*) { fake_classifier }) do
        result = FileProcessor.call(user: @user, file_data: file_data, filename: "movs.csv")

        assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
        assert_equal [ "COMPRA POS DESCONOCIDO" ], classified_activities
        known = result.candidates.find { |c| c.description == "COMPRA POS OXXO RIO ALTO" }
        assert_equal "Compras", known.category_name
        assert_equal "cached_user", known.classification_source
        unknown = result.candidates.find { |c| c.description == "COMPRA POS DESCONOCIDO" }
        assert_equal "fallback", unknown.classification_source
      end
    end

    test "reports that a PDF without a password is password protected" do
      result = FileProcessor.call(user: @user, file_data: encrypted_pdf_data_uri, filename: "stmt.pdf")

      assert_not result.ok?
      assert result.errors.any? { |message| message =~ /password|contrase[ñn]a/i }
    end

    test "reports an incorrect password when a password was supplied and the PDF still does not open" do
      result = FileProcessor.call(user: @user, file_data: encrypted_pdf_data_uri, filename: "stmt.pdf", password: "wrong")

      assert_not result.ok?
      assert result.errors.any? { |message| message =~ /incorrect|incorrecta/i }
    end

    test "does not persist or leak the supplied PDF password" do
      result = FileProcessor.call(user: @user, file_data: encrypted_pdf_data_uri,
                                  filename: "stmt.pdf", password: "supersecret")

      assert_not result.ok?
      all_text = [ result.errors, result.warnings, result.candidates.map(&:to_h) ].flatten.compact.join(" ")
      assert_not_includes all_text, "supersecret"
    end

    test "extracts transactions from a CSV deterministically" do
      csv = "Fecha,Descripcion,Valor\n2026-09-09,DIDI FOOD,45000\n"
      file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

      result = FileProcessor.call(user: @user, file_data: file_data, filename: "stmt.csv")

      assert result.ok?
      assert_equal 1, result.candidates.length
      assert_equal "DIDI FOOD", result.candidates.first.description
      assert_equal BigDecimal("45000"), result.candidates.first.amount
    end

    test "extracts signed debit amounts from bank CSV exports deterministically" do
      csv = "Fecha,Descripción,Valor Débito,Valor Crédito\r\n2026/09/10,COMPRA POS TIENDA D1,-52090.0,\r\n2026/09/11,CONSIGNACIÓN RECIBIDA,,85000.0\r\n"
      file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

      result = FileProcessor.call(user: @user, file_data: file_data, filename: "movs.csv")

      assert result.ok?
      expenses = result.candidates.select { |candidate| candidate.description == "COMPRA POS TIENDA D1" }
      assert_equal 1, expenses.length
      assert_equal BigDecimal("52090"), expenses.first.amount
      # Income-only rows are not turned into expenses.
      assert result.candidates.none? { |candidate| candidate.description == "CONSIGNACIÓN RECIBIDA" }
    end

    test "keeps UTF-8 accented headers when the file arrives as raw binary bytes" do
      csv = "Fecha,Descripción,Valor Débito,Valor Crédito\r\n2026/09/10,COMPRA POS TIENDA D1,-52090.0,\r\n"
      file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

      result = FileProcessor.call(user: @user, file_data: file_data, filename: "movs.csv")

      assert result.ok?
      assert_equal 1, result.candidates.length
      assert_equal "COMPRA POS TIENDA D1", result.candidates.first.description
    end

    test "decodes legacy windows-1252 bank exports without dropping accents" do
      csv = "Fecha,Descripción,Valor\r\n2026-09-09,COMPRA ÉXITO,45000\r\n".encode(Encoding::WINDOWS_1252)
      file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"

      result = FileProcessor.call(user: @user, file_data: file_data, filename: "movs.csv")

      assert result.ok?
      assert_equal 1, result.candidates.length
      assert_equal "COMPRA ÉXITO", result.candidates.first.description
    end

    test "surfaces the AI extraction error when tabular parsing and AI both fail" do
      csv = "Etiqueta,Dato\nCOMPRA POS,XYZ\n"
      file_data = "data:text/csv;base64,#{Base64.strict_encode64(csv)}"
      fake_extractor = Class.new do
        def call(text:, today: Date.current)
          { ok?: false, data: nil, error: "AI request failed (boom)" }
        end
      end.new

      # No AI keys: the structure-mapping tier stays out of the way.
      with_env({ "MISTRAL_API_KEY" => nil }) do
        stub_method(Ai::StatementExtractor, :new, ->(*) { fake_extractor }) do
          result = FileProcessor.call(user: @user, file_data: file_data, filename: "stmt.csv")

          assert_not result.ok?
          assert_includes result.errors.first, "AI request failed (boom)"
        end
      end
    end

    test "rejects an unsupported file extension" do
      result = FileProcessor.call(user: @user, file_data: "data:text/plain;base64,cGxhaW4=", filename: "notes.txt")

      assert_not result.ok?
    end

    # ---------------------------------------------------- structure mapping

    UNKNOWN_CSV_HEADERS = "Stamp,Label,Spent,Brought,Running"

    def unknown_format_csv
      csv = "#{UNKNOWN_CSV_HEADERS}\n2026-09-01,DIDI FOOD,45000,,1250000\n2026-09-02,UBER TRIP,22000,,1228000\n"
      "data:text/csv;base64,#{Base64.strict_encode64(csv)}"
    end

    def unknown_format_mapping_payload
      {
        mapping: {
          date_column: "Stamp", description_column: "Label", amount_column: nil,
          debit_column: "Spent", credit_column: "Brought", balance_column: "Running"
        },
        confidence: 0.96
      }.to_json
    end

    def stub_classifier
      fake = Class.new do
        define_method(:call) { |**_kwargs| { ok?: true, data: {}, error: nil } }
      end.new
      stub_method(Ai::CategoryClassifier, :new, ->(*) { fake }) { yield }
    end

    test "an unknown spreadsheet format is mapped once by the structure AI" do
      strong = FakeAiProvider.new(responses: [ unknown_format_mapping_payload ])
      result = nil

      stub_classifier do
        stub_method(Ai::Providers, :strong, ->(*) { strong }) do
          result = FileProcessor.call(user: @user, file_data: unknown_format_csv, filename: "odd.csv")
        end
      end

      assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
      assert_equal 2, result.candidates.size
      assert_equal "DIDI FOOD", result.candidates.first.description
      assert_equal BigDecimal("45000"), result.candidates.first.amount
      assert_equal Date.new(2026, 9, 1), result.candidates.first.date
      assert_equal 1, strong.calls.count

      stored = SpreadsheetFormatMapping.for_user(@user).find_by(
        fingerprint: SpreadsheetFormatMapping.fingerprint(UNKNOWN_CSV_HEADERS.split(","))
      )
      assert_not_nil stored
    end

    test "a known spreadsheet format reuses the mapping without any AI structure call" do
      headers = UNKNOWN_CSV_HEADERS.split(",")
      SpreadsheetFormatMapping.record!(
        user: @user, headers: headers,
        mapping: { "date_column" => "Stamp", "description_column" => "Label",
                   "amount_column" => nil, "debit_column" => "Spent",
                   "credit_column" => "Brought", "balance_column" => "Running" },
        source: "strong_ai"
      )

      strong = FakeAiProvider.new(responses: [])
      result = nil
      stub_classifier do
        stub_method(Ai::Providers, :strong, ->(*) { strong }) do
          result = FileProcessor.call(user: @user, file_data: unknown_format_csv, filename: "odd.csv")
        end
      end

      assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
      assert_equal 2, result.candidates.size
      assert_equal 0, strong.calls.count
    end

    test "structure mapping failures fall back to the full-text AI extraction" do
      strong = FakeAiProvider.new(responses: [ Ai::Provider::Error.new("AI HTTP 500") ])
      fake_extractor = Class.new do
        define_method(:call) do |text:, today: Date.current|
          { ok?: true, data: { sources: [], transactions: [
            { date: "2026-09-01", description: "DIDI FOOD", amount: 45_000, type: "expense", confidence: 0.9 }
          ] }, error: nil }
        end
      end.new

      result = nil
      stub_method(Ai::Providers, :strong, ->(*) { strong }) do
        stub_method(Ai::StatementExtractor, :new, ->(*) { fake_extractor }) do
          result = FileProcessor.call(user: @user, file_data: unknown_format_csv, filename: "odd.csv")
        end
      end

      assert result.ok?, "expected ok, got errors: #{result.errors.inspect}"
      assert_equal "DIDI FOOD", result.candidates.first.description
    end
  end
end
