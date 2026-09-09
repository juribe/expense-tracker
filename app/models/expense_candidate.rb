# frozen_string_literal: true

# A parsed expense that has NOT been persisted. Every ingestion method (text,
# image, and future WhatsApp/voice/email/PDF adapters) normalizes into this
# same structure. The Playground shows it for review; an expense is only
# created when the user explicitly confirms through Expenses::Create.
class ExpenseCandidate
  DEFAULT_CURRENCY = "COP"
  MAX_AMOUNT = BigDecimal("99_999_999.99")
  MIN_CONFIDENCE = 0.0
  MAX_CONFIDENCE = 1.0

  ATTRIBUTES = %i[
    amount currency category_id category_name description merchant
    date source confidence money_source_id money_source_name
  ].freeze

  attr_accessor(*ATTRIBUTES)
  attr_reader :errors

  def initialize(attributes = {})
    @errors = []
    ATTRIBUTES.each do |attribute|
      public_send("#{attribute}=", attributes[attribute])
    end
    self.currency = currency.presence || DEFAULT_CURRENCY
    self.source = source.presence || "playground"
    self.confidence = normalize_confidence(confidence)
  end

  # Rebuilds a candidate from JSON params (e.g. the create endpoint).
  def self.from_h(hash)
    hash = (hash.respond_to?(:to_unsafe_h) ? hash.to_unsafe_h : hash).symbolize_keys
    new(
      amount: parse_amount(hash[:amount]),
      currency: hash[:currency],
      category_id: hash[:category_id].presence&.to_i,
      category_name: hash[:category_name].presence,
      description: hash[:description].presence,
      merchant: hash[:merchant].presence,
      date: parse_date(hash[:date]),
      source: hash[:source],
      confidence: hash[:confidence],
      money_source_id: hash[:money_source_id].presence&.to_i,
      money_source_name: hash[:money_source_name].presence
    )
  end

  def valid?
    errors.clear
    validate_amount
    validate_currency
    validate_category
    validate_date
    errors.empty?
  end

  def invalid?
    !valid?
  end

  # Individual checks rendered by the pipeline/debug view.
  def checks
    [
      { label: "Amount present", passed: positive_amount? },
      { label: "Currency detected", passed: currency.present? },
      { label: "Category mapped", passed: category_id.present? || category_name.present? },
      { label: "Valid date", passed: date.present? }
    ]
  end

  def to_h
    ATTRIBUTES.each_with_object({}) do |attribute, hash|
      hash[attribute] = public_send(attribute)
    end
  end

  def as_json(*)
    to_h.merge(date: date&.iso8601, confidence: confidence)
  end

  private

  def normalize_confidence(value)
    return nil if value.blank?

    Float(value).clamp(MIN_CONFIDENCE, MAX_CONFIDENCE)
  rescue ArgumentError, TypeError
    nil
  end

  def self.parse_amount(value)
    return value if value.is_a?(Numeric)
    return nil if value.blank?

    BigDecimal(value.to_s.gsub(/[^0-9.\-]/, ""))
  rescue ArgumentError, TypeError
    nil
  end

  def self.parse_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    begin
      Date.iso8601(value.to_s)
    rescue ArgumentError, Date::Error, TypeError
      Date.parse(value.to_s)
    end
  rescue ArgumentError, Date::Error, TypeError
    nil
  end

  def positive_amount?
    amount.is_a?(Numeric) && amount.positive? && amount <= MAX_AMOUNT
  end

  def validate_amount
    if amount.nil?
      errors << "Amount is missing or could not be read."
    elsif !amount.is_a?(Numeric) || !amount.positive?
      errors << "Amount must be greater than zero."
    elsif amount > MAX_AMOUNT
      errors << "Amount exceeds the maximum allowed value."
    end
  end

  def validate_currency
    errors << "Currency is missing." if currency.blank?
  end

  def validate_category
    return if category_id.present? || category_name.present?

    errors << "No category could be mapped."
  end

  def validate_date
    if date.nil?
      errors << "Date is missing or invalid."
    elsif !date.is_a?(Date)
      errors << "Date is invalid."
    end
  end
end
