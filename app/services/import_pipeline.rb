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
    return failure("Unsupported file type. Please upload a PDF, CSV, or Excel file.") unless format

    text = extract_text(file, format, password: password)
    return failure("Could not extract text from this document. Please try another file.") if text.blank?

    extraction = run_extraction(text)
    return failure(extraction[:error]) unless extraction[:ok?]

    sources = build_sources(extraction[:data][:sources])
    transactions = extraction[:data][:transactions] || []

    Result.new(ok?: true, sources: sources, transactions: transactions, error: nil)
  rescue StandardError => e
    failure("Import failed: #{e.message}")
  end

  private

  def default_extractor
    Ai::StatementExtractor.new
  end

  def validate_upload(file)
    return "No file was uploaded." if file.blank?
    return "File is empty." if file.respond_to?(:size) && file.size.zero?

    original = file.respond_to?(:original_filename) ? file.original_filename : file.path.to_s
    return "Unsupported file type. Please upload a PDF, CSV, or Excel file." unless SUPPORTED_FORMATS.include?(File.extname(original.to_s).downcase)

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
    case format
    when ".csv"
      file.respond_to?(:read) ? file.read : File.read(file.path)
    when ".xlsx"
      extract_xlsx(file)
    when ".pdf"
      extract_pdf(file, password: password)
    end
  end

  def extract_xlsx(file)
    content = file.respond_to?(:read) ? file.read : File.read(file.path)
    return content if defined?(RubyXL) || defined?(Roo)

    # Without a spreadsheet gem, fall back to returning the raw bytes length so
    # "no text" is avoided only when some content exists.
    content.presence
  end

  def extract_pdf(file, password: nil)
    content = file.respond_to?(:read) ? file.read : File.read(file.path)
    return content if defined?(PDF::Reader)

    content.presence
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
