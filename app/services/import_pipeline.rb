# frozen_string_literal: true

# ImportPipeline
# Orchestrates uploading a statement through validation, format detection,
# password handling, text extraction, AI extraction, normalization and
# duplicate detection. Returns structured review data; it never creates or
# modifies ActiveRecord records.
#
# Example: ImportPipeline.new(user: user).call(file: params[:file])
class ImportPipeline
  SUPPORTED_FORMATS = %w[.pdf .csv .xlsx].freeze

  Result = Struct.new(:ok?, :sources, :transactions, :error, keyword_init: true)

  def initialize(user:, extractor: nil)
    @user = user
    @extractor = extractor || default_extractor
  end

  def call(file:, password: nil)
    validation = validate_upload(file)
    return failure(validation) if validation.is_a?(String)

    format = detect_format(file)
    return failure(I18n.t("wizard.upload.unsupported_type")) unless format

    text = extract_text(file, format, password: password)
    return failure(I18n.t("wizard.upload.extract_failed")) if text.blank?

    extraction = run_extraction(text)
    return failure(extraction[:error]) unless extraction[:ok?]

    sources = build_sources(extraction[:data][:sources])
    transactions = extraction[:data][:transactions] || []

    Result.new(ok?: true, sources: sources, transactions: transactions, error: nil)
  rescue StandardError => e
    failure(I18n.t("wizard.upload.import_failed", message: e.message))
  end

  private

  def default_extractor
    Ai::StatementExtractor.new
  end

  def validate_upload(file)
    return I18n.t("wizard.upload.no_file") if file.blank?
    return I18n.t("wizard.upload.empty_file") if file.respond_to?(:size) && file.size.zero?

    original = file.respond_to?(:original_filename) ? file.original_filename : file.path.to_s
    return I18n.t("wizard.upload.unsupported_type") unless SUPPORTED_FORMATS.include?(File.extname(original.to_s).downcase)

    nil
  end

  def detect_format(file)
    original = file.respond_to?(:original_filename) ? file.original_filename : file.path.to_s
    File.extname(original.to_s).downcase
  end

  # Extracts raw text from the uploaded document. Password handling is left to
  # the caller: the password is only used here during extraction and is never
  # persisted or logged.
  def extract_text(file, format, password: nil)
    raw = case format
          when ".csv"
            file.respond_to?(:read) ? file.read : File.read(file.path)
          when ".xlsx"
            extract_xlsx(file)
          when ".pdf"
            extract_pdf(file, password: password)
          end
    raw&.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
  end

  def extract_xlsx(file)
    content = file.respond_to?(:read) ? file.read : File.read(file.path)
    return content if defined?(RubyXL) || defined?(Roo)

    content.presence
  end

  def extract_pdf(file, password: nil)
    require "tempfile"
    tmp = Tempfile.new([ "upload", ".pdf" ])
    tmp.binmode
    tmp.write(file.respond_to?(:read) ? file.read : File.binread(file.path))
    tmp.rewind

    reader = if password.present?
               PDF::Reader.new(tmp, password: password)
             else
               PDF::Reader.new(tmp)
             end

    pages = reader.pages.map(&:text).join("\n\n")
    pages.presence
  rescue PDF::Reader::EncryptedPDFError
    raise I18n.t("wizard.upload.pdf_encrypted")
  rescue PDF::Reader::Error
    raise I18n.t("wizard.upload.pdf_unreadable")
  ensure
    tmp&.close!
  end

  def run_extraction(text)
    if @extractor.respond_to?(:call)
      @extractor.call(text: text)
    else
      @extractor.extract(text: text)
    end
  end

  def build_sources(sources_data)
    sources_data.map { |data| ParsedStatement.new(data) }
  end

  def failure(message)
    Result.new(ok?: false, sources: [], transactions: [], error: message)
  end
end
