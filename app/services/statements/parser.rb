# frozen_string_literal: true

module Statements
  # Parser
  # Entry point every uploaded credit-card / loan statement file is passed
  # through. Decodes the upload, extracts its content with the shared file
  # readers (password handling included), runs a matching layout adapter when
  # one is registered, and falls back to AI extraction otherwise. Returns a
  # canonical Statements::Document; never writes records.
  #
  #   result = Statements::Parser.call(user: user, file_data: data_uri,
  #                                    filename: "extracto.pdf", password: "1234")
  #   result.result # => Statements::Document
  class Parser
    def self.call(user:, file_data:, filename: nil, password: nil, extractor: nil)
      new(user: user, file_data: file_data, filename: filename,
          password: password, extractor: extractor).call
    end

    def initialize(user:, file_data:, filename: nil, password: nil, extractor: nil)
      @user = user
      @file_data = file_data
      @filename = filename.to_s.presence || "uploaded_file"
      @password = password.to_s.presence
      @extractor = extractor || Ai::StatementExtractor.new
      @errors = []
      @warnings = []
    end

    def call
      binary = Expenses::Inputs::File.binary(@file_data)
      return failure("Could not decode file data.") if binary.nil?

      extension = Expenses::Inputs::File.extension(@file_data, @filename)
      unless extension.in?(Expenses::FileImport::Pipeline::SUPPORTED_EXTENSIONS)
        return failure(I18n.t("wizard.upload.unsupported_type"))
      end

      extraction = read_file(binary, extension)
      return failure(I18n.t("wizard.upload.extract_failed")) if extraction.text.blank?

      parse_document(extraction)
    end

    private

    def read_file(binary, extension)
      reader = Expenses::FileImport::Readers.for(extension)
      reader.call(binary: binary, errors: @errors, warnings: @warnings, password: @password)
    end

    def parse_document(extraction)
      adapter = Statements::Adapters.for(extraction.text)
      return ServiceResult.success(adapter.call(extraction)) if adapter

      ai_document(extraction)
    end

    def ai_document(extraction)
      result = @extractor.call(text: extraction.text)
      return failure(result[:error].presence || I18n.t("wizard.upload.extract_failed")) unless result[:ok?]

      ServiceResult.success(build_document(result[:data], engine: :ai))
    rescue Ai::StatementExtractor::ExtractionError => e
      failure(e.message)
    end

    def build_document(data, engine:)
      source_data = Array(data[:sources]).first
      Statements::Document.new(
        engine: engine,
        summary: Statements::Summary.from_h(data[:summary]),
        movements: Array(data[:transactions]),
        source: source_data ? ParsedStatement.new(source_data) : nil
      )
    end

    def failure(message)
      ServiceResult.error(@errors.empty? ? [ message ] : @errors)
    end
  end
end
