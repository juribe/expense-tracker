# frozen_string_literal: true

class ExpenseParser
  class DateService
    WEEKDAYS = {
      "lunes" => 1, "martes" => 2, "miercoles" => 3, "jueves" => 4,
      "viernes" => 5, "sabado" => 6, "domingo" => 0
    }.freeze

    # Returns [Date, confidence] when an explicit date expression is found.
    def self.detect_date(text, today: Date.current)
      if text.match?(/\bhoy\b/)
        [ today, 0.95 ]
      elsif text.match?(/\banteayer\b/)
        [ today - 2, 0.85 ]
      elsif text.match?(/\bayer\b/)
        [ today - 1, 0.95 ]
      else
        detect_weekday_date(text, today: today)
      end
    end

    def self.detect_weekday_date(text, today: Date.current)
      match = text.match(/\b(lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b/)
      return nil unless match

      target_wday = WEEKDAYS[match[1]]
      days_back = (today.wday - target_wday - 7) % 7
      days_back = 7 if days_back.zero?
      [ today - days_back, 0.85 ]
    end

    def self.parse_iso_date(value)
      return value if value.is_a?(Date)
      return nil if value.blank?

      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      begin
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
