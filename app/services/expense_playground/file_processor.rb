# frozen_string_literal: true

require "csv"

module ExpensePlayground
  # Processes uploaded files (PDF, CSV, Excel) through the import pipeline.
  # Extracts text from the file, runs AI extraction, and returns structured
  # candidates for preview and batch creation.
  #
  #   result = FileProcessor.call(user: user, file_data: "data:...", filename: "stmt.pdf")
  #   result.ok?        # => true
  #   result.candidates # => [ExpenseCandidate, ...]
  #   result.sources    # => [ParsedStatement, ...]
  class FileProcessor
    SUPPORTED_EXTENSIONS = %w[pdf csv xlsx xls].freeze

    Result = Struct.new(:ok?, :candidates, :sources, :errors, :warnings, :step_results, :duplicates,
                         keyword_init: true)

    class << self
      def call(user:, file_data:, filename: nil, password: nil)
        new(user: user, file_data: file_data, filename: filename, password: password).call
      end
    end

    def initialize(user:, file_data:, filename: nil, password: nil)
      @user = user
      @file_data = file_data
      @filename = filename.to_s.presence || "uploaded_file"
      @password = password.to_s.presence
      @errors = []
      @warnings = []
      @step_results = {}
      @duplicates = []
    end

    def call
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      binary = decode_file_data
      return failure("Could not decode file data.") if binary.nil?

      ext = detect_extension
      return failure(I18n.t("wizard.upload.unsupported_type")) unless ext.in?(SUPPORTED_EXTENSIONS)

      text = extract_text(binary, ext)
      return failure(@errors.first.presence || I18n.t("wizard.upload.extract_failed")) if text.blank?

      # Favor deterministic parsing for tabular files before spending an AI
      # request: CSV columns are usually machine-readable. Only fall back to
      # the AI extractor when the deterministic pass finds nothing.
      candidates, sources, engine = run_candidates(binary, ext, text)
      if candidates.empty? && engine == :ai
        return failure(@errors.first.presence || I18n.t("wizard.upload.extract_failed"))
      end
      if candidates.empty?
        @errors << I18n.t("playground.file_no_transactions")
        return failure(@errors.first)
      end

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      @step_results[:duration_ms] = duration_ms
      @step_results[:engine] = engine

      enrich_candidates(candidates, engine, sources)

      Result.new(
        ok?: true,
        candidates: candidates,
        sources: sources,
        errors: @errors.dup,
        warnings: @warnings.dup,
        step_results: @step_results,
        duplicates: @duplicates
      )
    rescue StandardError => e
      Rails.logger.error("[FileProcessor] #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}")
      failure(e.message)
    end

    private

    # Returns [candidates, sources, engine]. Deterministic CSV parsing runs
    # first; the AI extractor is only invoked when it produces nothing.
    def run_candidates(binary, ext, text)
      if %w[csv xlsx xls].include?(ext)
        deterministic = build_deterministic_candidates(binary, ext)
        return [ deterministic, [], :deterministic ] if deterministic.any?

        @warnings << "Tabular parsing could not be matched reliably; falling back to AI extraction."
      end

      extraction = run_extraction(text)
      unless extraction[:ok?]
        @errors << extraction[:error].presence || I18n.t("wizard.upload.extract_failed")
        return [ [], [], :ai ]
      end

      candidates = build_candidates(extraction.dig(:data, :transactions) || [])
      sources = build_sources(extraction.dig(:data, :sources) || [])
      [ candidates, sources, :ai ]
    end

    def decode_file_data
      base64 = @file_data.to_s.sub(/\Adata:[^;]+;base64,/, "")
      Base64.decode64(base64)
    rescue ArgumentError
      nil
    end

    def detect_extension
      ext = File.extname(@filename).delete(".").downcase
      return ext if ext.present? && ext.in?(SUPPORTED_EXTENSIONS)

      mime_ext = @file_data.to_s.match(/\Adata:([^;]+);base64,/)&.[](1)
      case mime_ext
      when "application/pdf" then "pdf"
      when "text/csv" then "csv"
      when "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" then "xlsx"
      when "application/vnd.ms-excel" then "xls"
      end
    end

    def extract_text(binary, ext)
      case ext
      when "csv"
        extract_csv(binary)
      when "xlsx", "xls"
        extract_xlsx(binary)
      when "pdf"
        extract_pdf(binary)
      end
    end

    # Uploaded binaries are raw byte strings. Modern bank exports are UTF-8;
    # legacy latin-1 ones would make every accented character invalid in a
    # UTF-8 view, so fall back to Windows-1252 when the bytes are not valid
    # UTF-8. Never call String#encode straight from ASCII-8BIT: it treats
    # multi-byte UTF-8 sequences as invalid and silently strips accents.
    def decode_to_utf8(binary)
      utf8 = binary.dup.force_encoding(Encoding::UTF_8)
      return utf8.scrub("") if utf8.valid_encoding?

      binary.dup.force_encoding(Encoding::WINDOWS_1252)
            .encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
    end

    def extract_csv(binary)
      require "stringio"
      csv_io = StringIO.new(decode_to_utf8(binary))
      rows = CSV.parse(csv_io, headers: true)
      return nil if rows.empty?

      headers = rows.headers.compact.map(&:to_s)
      lines = rows.map do |row|
        fields = headers.map { |h| row[h].to_s.strip }.reject(&:blank?)
        fields.join(" | ")
      end
      lines.join("\n")
    end

    def extract_xlsx(binary)
      require "tempfile"
      tmp = Tempfile.new([ "upload", ".xlsx" ])
      tmp.binmode
      tmp.write(binary)
      tmp.rewind

      if defined?(Roo::Spreadsheet)
        extract_with_roo(tmp.path)
      else
        extract_xlsx_raw(binary)
      end
    ensure
      tmp&.close!
    end

    def extract_with_roo(path)
      spreadsheet = Roo::Spreadsheet.open(path)
      sheet = spreadsheet.sheet(0)
      return nil unless sheet

      rows = []
      sheet.each_row_streaming(Array: true) do |row|
        cells = row.map { |cell| cell.to_s.strip }.reject(&:blank?)
        rows << cells.join(" | ") if cells.any?
      end
      rows.join("\n")
    end

    def extract_xlsx_raw(binary)
      require "zip"
      Zip::InputStream.open(StringIO.new(binary)) do |io|
        while (entry = io.get_next_entry)
          next unless entry.name.include?("sheet") && entry.name.end_with?(".xml")

          content = io.read
          cells = content.scan(/<v>([^<]+)<\/v>/).flatten
          return cells.each_slice(10).map { |slice| slice.join(" | ") }.join("\n") if cells.any?
        end
      end
      nil
    rescue StandardError
      nil
    end

    def extract_pdf(binary)
      require "tempfile"
      tmp = Tempfile.new([ "upload", ".pdf" ])
      tmp.binmode
      tmp.write(binary)
      tmp.rewind

      reader = if @password.present?
        PDF::Reader.new(tmp, password: @password)
      else
        PDF::Reader.new(tmp)
      end

      pages = reader.pages.map(&:text).join("\n\n")
      pages.presence
    rescue PDF::Reader::EncryptedPDFError
      # The caller presents the password prompt when none was supplied; when
      # one was supplied and the document is still locked, that is an
      # incorrect-password error. Both errors are surfaced to the user.
      @errors << if @password.present?
        I18n.t("wizard.upload.password_error")
      else
        I18n.t("wizard.upload.pdf_encrypted")
      end
      nil
    rescue PDF::Reader::Error
      @errors << I18n.t("wizard.upload.pdf_unreadable")
      nil
    ensure
      tmp&.close!
    end

    def run_extraction(text)
      extractor = Ai::StatementExtractor.new
      if extractor.respond_to?(:call)
        extractor.call(text: text)
      else
        extractor.extract(text: text)
      end
    end

    DATE_HEADERS = /\b(?:fecha|fech|date|posted|transaction date|fch|movimiento)\b/i
    DESC_HEADERS = /\b(?:descripcion|descripci[oó]n|description|detalle|concepto|concept|actividad|activity|comercio|comerciante|merchant|referencia|reference|nombre|name)\b/i
    AMOUNT_HEADERS = /\b(?:valor|monto|amount|debito|cargo|credito|cr[eé]dito|debit|credit|importe|total|valor pagado)\b/i
    EXPENSE_HEADERS = /\b(?:debito|cargo|debit|expense|valor)\b/i
    INCOME_HEADERS = /\b(?:credito|cr[eé]dito|credit|income|valor)\b/i

    # Best-effort deterministic parser for tabular statements. Column headers
    # are matched through flexible aliases so common bank exports (spanish and
    # english) parse without any AI call.
    def build_deterministic_candidates(binary, ext)
      rows, headers = extract_tabular_rows(binary, ext)
      return [] if rows.empty? || headers.empty?

      date_idx, desc_idx, amount_idx, expense_only_idx = index_columns(headers)

      categories = Category.for_user(@user).order(:name).to_a

      rows.filter_map do |row|
        amount_source = sum_amount_cells(row, amount_idx, expense_only_idx)
        next if amount_source.blank?

        amount = parse_amount(amount_source)
        next if amount.nil?

        description = cell_text(desc_idx && row[desc_idx])
        next if description.blank?

        candidate = ExpenseCandidate.new(
          amount: amount.abs,
          currency: ExpenseCandidate::DEFAULT_CURRENCY,
          category_id: nil,
          category_name: "Others",
          description: description,
          merchant: nil,
          date: parse_date(cell_text(date_idx && row[date_idx])),
          source: "playground_file",
          confidence: 0.9,
          money_source_id: nil,
          money_source_name: nil
        )
        candidate.valid? ? candidate : nil
      end
    rescue StandardError => e
      Rails.logger.warn("[FileProcessor] deterministic parse skipped: #{e.class}: #{e.message}")
      []
    end

    def extract_tabular_rows(binary, ext)
      if ext == "csv"
        require "stringio"
        text = decode_to_utf8(binary).delete("\r")
        table = CSV.parse(text, headers: true)
        return [ table.map { |row| row.fields }, table.headers.compact.map(&:to_s) ]
      end

      [ [], [] ]
    end

    def index_columns(headers)
      normalized = headers.map { |h| h.to_s.downcase.gsub(/\s+/, " ").strip }

      date_idx = normalized.index { |h| h.match?(DATE_HEADERS) }
      desc_idx = normalized.index { |h| h.match?(DESC_HEADERS) }
      expense_idx = normalized.index { |h| h.match?(EXPENSE_HEADERS) && !h.match?(INCOME_HEADERS) && !h.match?(DESC_HEADERS) }
      # Prefer a dedicated debit/cargo column for the amount; otherwise fall
      # back to a generic "valor"/"amount" column.
      generic_idx = normalized.index { |h| h.match?(AMOUNT_HEADERS) }

      [ date_idx, desc_idx, expense_idx || generic_idx, expense_idx ]
    end

    # Picks the row cell that carries the transaction's absolute amount. When
    # the statement splits debits and credits into separate columns, returns
    # the debit column value when present (expenses), the credit one otherwise.
    def sum_amount_cells(row, amount_idx, expense_idx)
      return row[amount_idx] if amount_idx.present?

      row.to_a.find { |cell| parse_amount(cell_text(cell)) }
    end

    def cell_text(value)
      value.to_s.strip.presence
    end

    def build_candidates(transactions)
      categories = Category.for_user(@user).order(:name).to_a

      transactions.filter_map do |tx|
        next unless tx.is_a?(Hash)

        tx = tx.transform_keys(&:to_s)
        description = tx["description"].to_s.strip
        amount = parse_amount(tx["amount"])
        next if description.blank? || amount.nil?

        date = parse_date(tx["date"])
        category_name = tx["category"].to_s.strip.presence || "Others"
        category = resolve_category(categories, category_name)

        ExpenseCandidate.new(
          amount: amount.abs,
          currency: ExpenseCandidate::DEFAULT_CURRENCY,
          category_id: category&.id,
          category_name: category&.name || category_name,
          description: description,
          merchant: nil,
          date: date,
          source: "playground_file",
          confidence: normalize_confidence(tx["confidence"]),
          money_source_id: nil,
          money_source_name: nil
        )
      end
    end

    def build_sources(sources_data)
      sources_data.map { |data| ParsedStatement.new(data) }
    end

    def resolve_category(categories, name)
      normalized = normalize_name(name)
      categories.find { |c| normalize_name(c.name) == normalized } ||
        categories.find { |c| normalize_name(c.name).include?(normalized) || normalized.include?(normalize_name(c.name)) }
    end

    def normalize_name(text)
      text.to_s.downcase.tr("áéíóúü", "aeiouu").squish
    end

    def parse_amount(value)
      numeric = value.is_a?(Numeric) ? value.to_f : parse_amount_text(value.to_s)
      return nil unless numeric.is_a?(Numeric) && numeric.finite? && numeric != 0.0

      BigDecimal(numeric.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_amount_text(text)
      return 0.0 if text.blank?

      cleaned = text.gsub(/[^0-9.,\-]/, "")
      return 0.0 if cleaned.blank? || cleaned == "-"

      if cleaned.match?(/\A-?\d{1,3}(?:\.\d{3})+,\d+\z/)
        cleaned.delete(".").tr(",", ".").to_f
      elsif cleaned.match?(/\A-?\d{1,3}(?:\.\d{3})+\z/)
        cleaned.delete(".").to_f
      elsif cleaned.match?(/\A-?\d+,\d+\z/)
        cleaned.tr(",", ".").to_f
      else
        cleaned.to_f
      end
    end

    def parse_date(value)
      return Date.current if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError, Date::Error, TypeError
      Date.parse(value.to_s)
    rescue ArgumentError, Date::Error, TypeError
      nil
    end

    def normalize_confidence(value)
      confidence = value.is_a?(Numeric) ? value : Float(value.to_s)
      confidence.clamp(0.0, 1.0)
    rescue ArgumentError, TypeError
      0.5
    end

    # Applies the reuse-aware enrichment layer to the extracted candidates:
    # classification reuse, money source reuse within this import, and
    # duplicate-flagging against existing transactions and the batch itself.
    def enrich_candidates(candidates, engine, sources = [])
      classify_activities(candidates, engine)
      resolve_money_sources(candidates, sources)
      flags = DuplicateDetector.new(user: @user).flag(candidates)
      @duplicates = candidates.each_index.select { |index| flags[index] }
      candidates
    end

    # Classification priority: cached user overwrite → cached AI/rule → rule →
    # batch AI classification (deterministic imports only) → whatever the base
    # candidate already carries (statement extractor result). Each unique
    # activity is resolved once and reused for the rest of the batch.
    def classify_activities(candidates, engine)
      results = {}
      fallbacks = {}
      candidates.each do |candidate|
        activity = candidate.description.to_s
        next if activity.blank?

        key = ActivityClassification.normalize_name(activity) || activity
        result = results[key] ||= Expenses::ActivityClassifier.call(user: @user, activity: activity)

        if result[:source] == "fallback"
          fallbacks[key] = activity
          candidate.classification_source = engine == :ai ? "ai" : "fallback"
          candidate.suggested_category_id = candidate.category_id
          candidate.suggested_category_name = candidate.category_name
          next
        end

        candidate.classification_source = result[:source]
        candidate.suggested_category_id = result[:category].id if result[:category]
        candidate.suggested_category_name = result[:category]&.name
        next unless result[:category]

        candidate.category_id = result[:category].id
        candidate.category_name = result[:category].name
      end

      ai_classify_fallbacks(candidates, fallbacks, engine)
    end

    # Deterministic extraction (CSV/Excel) skips AI parsing, so without
    # classification reuse every row would land as "Others". Batch-classify
    # the activities with no stored/rule mapping in a single request.
    def ai_classify_fallbacks(candidates, fallbacks, engine)
      return if engine == :ai || fallbacks.empty? || ENV["MISTRAL_API_KEY"].blank?

      categories = Category.for_user(@user).where(category_type: "expense").order(:name)
      response = Ai::CategoryClassifier.new.call(activities: fallbacks.values.uniq,
                                                 categories: categories.map(&:name))
      return unless response[:ok?]

      assignments = response[:data] || {}
      candidates.each do |candidate|
        activity = candidate.description.to_s
        key = ActivityClassification.normalize_name(activity) || activity
        next unless fallbacks.key?(key)

        category_name = assignments[key].to_s.presence
        next unless category_name

        category = categories.find { |item| item.name.casecmp?(category_name) }
        next unless category

        candidate.category_id = category.id
        candidate.category_name = category.name
        candidate.suggested_category_id = category.id
        candidate.suggested_category_name = category.name
        candidate.classification_source = "ai"
      end
    end

    # Money Source resolution priority: keyword detection over the transaction
    # description (reused across equal activities within the import) wins; the
    # statement-level source (verified by its account/card number) is assigned
    # to everything else so a statement import never lands unlinked.
    def resolve_money_sources(candidates, sources = [])
      statement_source = statement_money_source(sources)
      detector = MoneySources::Detector.new(user: @user)
      resolved = {}
      candidates.each do |candidate|
        activity = candidate.description.to_s
        key = ActivityClassification.normalize_name(activity) || activity.presence
        found = detected_from_cache = nil
        if resolved.key?(key)
          found = resolved[key]
          detected_from_cache = found.present?
        else
          found = detect_money_source(detector, activity)
          resolved[key] = found
        end

        if found
          candidate.money_source_id = found.id
          candidate.money_source_name = found.name
          candidate.money_source_source = detected_from_cache ? "reused_in_import" : "detected"
        elsif statement_source
          candidate.money_source_id = statement_source.id
          candidate.money_source_name = statement_source.name
          candidate.money_source_source = "statement"
        else
          candidate.money_source_source = "missing"
        end
      end
    end

    def detect_money_source(detector, text)
      detector.call(text)
    rescue StandardError
      nil
    end

    # Matches the statement's extracted source against the user's own sources
    # (verified by the account/card last four, else by a unique bank+kind
    # match), so every candidate inherits the owning source even when no
    # transaction description mentions a keyword.
    def statement_money_source(sources)
      Array(sources).filter_map do |statement|
        by_statement_identifier(statement) || by_statement_bank_and_kind(statement)
      end.first
    end

    def by_statement_identifier(statement)
      digits = (statement.identifier.presence || statement.card_last_four.presence).to_s.gsub(/\D/, "")
      last4 = digits[-4..]
      return nil unless last4&.length == 4

      match = MoneySources::Match.call(user: @user, card_last_four: last4)
      match if match.is_a?(MoneySource)
    end

    def by_statement_bank_and_kind(statement)
      bank = statement.bank.to_s.strip
      kind = statement.kind.to_s
      return nil if bank.blank? || kind.blank?

      matches = @user.money_sources.active.select do |source|
        source.kind == kind && normalize_name(source.bank) == normalize_name(bank)
      end
      matches.one? ? matches.first : nil
    end

    def failure(message)
      Result.new(ok?: false, candidates: [], sources: [], errors: [ message ],
                 warnings: @warnings.dup, step_results: @step_results, duplicates: @duplicates)
    end
  end
end
