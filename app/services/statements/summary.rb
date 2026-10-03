# frozen_string_literal: true

module Statements
  # Summary
  # Value object for the statement-level totals an apply-payment flow needs:
  # total due, minimum payment, interest charged, due date and statement date.
  # Amounts are coerced to BigDecimal and dates to Date; anything unparseable
  # stays nil. Never touches ActiveRecord records.
  #
  # Example: Statements::Summary.from_h({ "total_due" => "1.250.300", "due_date" => "2026-09-04" })
  class Summary
    ATTRIBUTES = %i[total_due min_payment interest_charged due_date statement_date].freeze
    MONEY_FIELDS = %i[total_due min_payment interest_charged].freeze
    DATE_FIELDS = %i[due_date statement_date].freeze

    attr_accessor(*ATTRIBUTES)

    def self.from_h(hash)
      new(hash || {})
    end

    def initialize(attributes = {})
      attrs = (attributes || {}).to_h.symbolize_keys
      ATTRIBUTES.each { |attribute| public_send("#{attribute}=", attrs[attribute]) }
      MONEY_FIELDS.each { |field| public_send("#{field}=", to_decimal(public_send(field))) }
      DATE_FIELDS.each { |field| public_send("#{field}=", to_date(public_send(field))) }
    end

    def present?
      ATTRIBUTES.any? { |attribute| public_send(attribute).present? }
    end

    def blank?
      !present?
    end

    # String-keyed JSON-safe form for the review round-trip.
    def to_h
      ATTRIBUTES.each_with_object({}) do |attribute, hash|
        value = public_send(attribute)
        hash[attribute.to_s] = value.is_a?(Date) ? value.iso8601 : value&.to_s
      end
    end

    private

    def to_decimal(value)
      return nil if value.blank?

      BigDecimal(MoneyFormat.normalize(value))
    rescue ArgumentError, TypeError
      nil
    end

    def to_date(value)
      return value if value.is_a?(Date) || value.nil?

      Date.iso8601(value.to_s)
    rescue ArgumentError, Date::Error, TypeError
      begin
        Date.parse(value.to_s)
      rescue ArgumentError, Date::Error, TypeError
        nil
      end
    end
  end
end
