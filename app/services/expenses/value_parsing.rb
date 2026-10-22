# frozen_string_literal: true

module Expenses
  # Stateless value heuristics shared by the file import pipeline. Extracted
  # from FileProcessor so row shaping, resolution and enrichment code can
  # reuse the same amount/date/confidence rules instead of re-deriving them.
  module ValueParsing
    extend self

    # Accepts numerics or free text and returns a BigDecimal, or nil when the
    # value carries no usable amount (blank, non-finite, zero). `allow_zero`
    # keeps zero values (balances, limits and rates can legitimately be 0).
    def parse_amount(value, allow_zero: false)
      numeric = value.is_a?(Numeric) ? value.to_f : parse_amount_text(value.to_s)
      return nil unless numeric.is_a?(Numeric) && numeric.finite? && (allow_zero || numeric != 0.0)

      BigDecimal(numeric.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def parse_amount_text(text)
      cleaned = text.to_s.gsub(/[^0-9.,'\-]/, "")
      return 0.0 if cleaned.blank? || cleaned == "-"

      negative = cleaned.start_with?("-")
      value = normalize_amount_text(cleaned.delete("-"))
      return 0.0 if value.nil?

      negative ? -value : value
    end

    # A separator followed by one or two digits is a decimal separator;
    # followed by three digits it groups thousands, with either comma or dot.
    # "22.209,60" => 22209.60, "5,400" and "5.400" => 5400.
    def normalize_amount_text(text)
      if (match = text.match(/\A(\d{1,3}(?:['.,]\s?\d{3})+)([.,])(\d{1,2})\z/))
        "#{match[1].delete("'.,").gsub(/\s+/, "")}.#{match[3]}".to_f
      elsif text.match?(/\A\d{1,3}(?:['.,]\s?\d{3})+\z/)
        text.delete("'.,").gsub(/\s+/, "").to_f
      elsif text.match?(/\A\d+[.,]\d{1,2}\z/)
        text.tr(",", ".").to_f
      else
        text.delete("'").tr(",", ".").to_f
      end
    end

    # ISO dates first (bank exports), then a free-form parse; blank values
    # land on the import date so a row is never dropped for missing dates.
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

    # Accent-insensitive comparison key used for category matching and for
    # every per-import cache keyed by activity name.
    def normalize_name(text)
      text.to_s.downcase.tr("áéíóúü", "aeiouu").squish
    end
  end
end
