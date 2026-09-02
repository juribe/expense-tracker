# frozen_string_literal: true

# MoneyFormat
# Normalizes money values from the two formats they can arrive in:
#   - Colombian display ("97.254.852,58"): dots are thousands, the first comma
#     is the decimal one; extra commas are dropped.
#   - Machine format ("972548.58", what the browser input mask submits): a
#     single dot followed by 1-2 digits is a decimal separator and is kept.
# Returns a BigDecimal-parseable string ("972548.58").
#
# Example: MoneyFormat.normalize("1.234.567,89") # => "1234567.89"
class MoneyFormat
  def self.normalize(value)
    return value if value.blank?

    cleaned = value.to_s.gsub(/[$ ]/, "")
    # Only handle numeric-looking strings; anything else passes through.
    return cleaned unless cleaned.match?(/\A-?[\d.,]+\z/) && cleaned.match?(/\d/)

    if cleaned.include?(",")
      without_thousands = cleaned.delete(".")
      comma = without_thousands.index(",")
      return without_thousands if comma.nil?

      "#{without_thousands[0...comma]}.#{without_thousands[(comma + 1)..].delete(',')}"
    elsif cleaned.match?(/\A-?\d+\.\d{1,2}\z/)
      cleaned
    else
      cleaned.delete(".")
    end
  end
end
