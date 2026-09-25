# frozen_string_literal: true

module ExpenseResolver
  module Dates
    class Service
      WEEKDAYS = {
        "lunes" => 1, "martes" => 2, "miercoles" => 3, "jueves" => 4,
        "viernes" => 5, "sabado" => 6, "domingo" => 0
      }.freeze

      # Returns [Date, confidence] when an explicit date expression is found.
      def self.detect_date(text, today: Date.current)
        return nil if text.blank?

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

      # Every distinct date a fragment resolves to (relative words + weekdays).
      # Used to flag ambiguous fragments that mention several different dates.
      def self.scan_dates(text, today: Date.current)
        return [] if text.blank?

        dates = []
        dates << today if text.match?(/\bhoy\b/)
        dates << today - 2 if text.match?(/\banteayer\b/)
        dates << today - 1 if text.match?(/\bayer\b/)
        text.scan(WEEKDAY_REGEX).flatten.each do |word|
          dates << weekday_date(word, today)
        end
        dates.uniq
      end

      WEEKDAY_REGEX = /\b(lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b/

      def self.detect_weekday_date(text, today: Date.current)
        match = text.match(WEEKDAY_REGEX)
        return nil unless match

        [ weekday_date(match[1], today), 0.85 ]
      end

      def self.weekday_date(word, today)
        target_wday = WEEKDAYS[word]
        days_back = (today.wday - target_wday - 7) % 7
        days_back = 7 if days_back.zero?
        today - days_back
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
end
