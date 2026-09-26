# frozen_string_literal: true

module Expenses
  module FileImport
    # Orchestrates a file import: decode the upload, pick the format reader
    # (strategy per extension), favor deterministic tabular parsing before
    # spending an AI request, and apply the reuse-aware enrichment layer to
    # the extracted candidates.
    class Pipeline
      SUPPORTED_EXTENSIONS = %w[pdf csv xlsx xls].freeze

      def self.call(user:, file_data:, filename: nil, password: nil)
        new(user: user, file_data: file_data, filename: filename, password: password).call
      end

      def initialize(user:, file_data:, filename: nil, password: nil)
        @user = user
        @file_data = file_data
        @filename = filename.to_s.presence || "uploaded_file"
        @password = password.to_s.presence
        @context = ImportContext.new(user)
        @errors = []
        @warnings = []
        @step_results = {}
        @duplicates = []
      end

      def call
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        binary = Expenses::Inputs::File.binary(@file_data)
        return failure("Could not decode file data.") if binary.nil?

        ext = Expenses::Inputs::File.extension(@file_data, @filename)
        return failure(I18n.t("wizard.upload.unsupported_type")) unless ext.in?(SUPPORTED_EXTENSIONS)

        extraction = read_file(binary, ext)
        return failure(@errors.first.presence || I18n.t("wizard.upload.extract_failed")) if extraction.text.blank?

        candidates, sources, engine = run_candidates(ext, extraction)
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

      def read_file(binary, ext)
        reader = Readers.for(ext)
        return Readers::Extraction.empty unless reader

        reader.call(binary: binary, errors: @errors, warnings: @warnings, password: @password)
      end

      # Returns [candidates, sources, engine]. Deterministic tabular parsing
      # runs first; the AI statement extractor is only invoked when it
      # produces nothing.
      def run_candidates(ext, extraction)
        if %w[csv xlsx xls].include?(ext)
          deterministic = build_deterministic_candidates(extraction)
          return [ deterministic, [], :deterministic ] if deterministic.any?

          @warnings << "Tabular parsing could not be matched reliably; falling back to AI extraction."
        end

        ai_candidates(extraction)
      end

      def build_deterministic_candidates(extraction)
        return [] if extraction.rows.empty? || extraction.headers.empty?

        mapping = TabularParser.call(user: @user, headers: extraction.headers, rows: extraction.rows)
        return [] if mapping.nil?

        CandidateBuilder.new(context: @context).from_tabular_rows(extraction.rows, mapping)
      rescue StandardError => e
        Rails.logger.warn("[FileProcessor] deterministic parse skipped: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        []
      end

      def ai_candidates(extraction)
        result = run_extraction(extraction.text)
        unless result[:ok?]
          @errors << result[:error].presence || I18n.t("wizard.upload.extract_failed")
          return [ [], [], :ai ]
        end

        builder = CandidateBuilder.new(context: @context)
        candidates = builder.from_transactions(result.dig(:data, :transactions) || [])
        sources = builder.statements(result.dig(:data, :sources) || [])
        [ candidates, sources, :ai ]
      end

      def run_extraction(text)
        extractor = Ai::StatementExtractor.new
        if extractor.respond_to?(:call)
          extractor.call(text: text)
        else
          extractor.extract(text: text)
        end
      end

      # Applies the reuse-aware enrichment layer to the extracted candidates:
      # classification reuse, money source reuse within this import, and
      # duplicate-flagging against existing transactions and the batch itself.
      def enrich_candidates(candidates, engine, sources = [])
        Enrichers::Activity.new(user: @user).call(candidates, engine)
        Enrichers::MoneySource.new(user: @user).call(candidates, sources)
        Enrichers::Confidence.new.call(candidates)
        flags = ExpensePlayground::DuplicateDetector.new(user: @user).flag(candidates)
        @duplicates = candidates.each_index.select { |index| flags[index] }
        candidates
      end

      def failure(message)
        Result.new(ok?: false, candidates: [], sources: [], errors: [ message ],
                   warnings: @warnings.dup, step_results: @step_results, duplicates: @duplicates)
      end
    end
  end
end
