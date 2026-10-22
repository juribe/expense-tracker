# frozen_string_literal: true

module ExpenseResolver
  module Dates
    class Service
      WEEKDAYS = {
        "lunes" => 1, "martes" => 2, "miercoles" => 3, "jueves" => 4,
        "viernes" => 5, "sabado" => 6, "domingo" => 0
      }.freeze

      MONTHS = {
        "enero" => 1, "febrero" => 2, "marzo" => 3, "abril" => 4,
        "mayo" => 5, "junio" => 6, "julio" => 7, "agosto" => 8,
        "septiembre" => 9, "setiembre" => 9, "octubre" => 10,
        "noviembre" => 11, "diciembre" => 12
      }.freeze

      MONTH_ALTERNATION = MONTHS.keys.sort_by(&:length).reverse.join("|")

      # A weekday word glued to a calendar date ("jueves, 22 de octubre de
      # 2026") describes that date; it is consumed with it when masking so the
      # weekday fallback never resolves the date to the previous week.
      WEEKDAY_PREFIX = /(?:(?:lunes|martes|miercoles|jueves|viernes|sabado|domingo)\b[,.]?\s*)?/

      # "22 de octubre de 2026" / "22 de octubre" — the month word makes the
      # leading number a day, never an amount.
      TEXTUAL_DATE_REGEX = /#{WEEKDAY_PREFIX}\b(\d{1,2})\s+de\s+(#{MONTH_ALTERNATION})(?:\s+(?:de|del)\s+(\d{4}))?\b/i

      # "22/10/2026" / "22-10-2026" — day first, as written in Spanish.
      NUMERIC_DATE_REGEX = /#{WEEKDAY_PREFIX}(?<!\d)(\d{1,2})[\/\-](\d{1,2})[\/\-](\d{2,4})(?!\d)/i

      TIME_REGEX = /\b\d{1,2}:\d{2}(?::\d{2})?\b/

      # Returns [Date, confidence] when an explicit date expression is found.
      # An explicit calendar date outranks a weekday word: "jueves, 22 de
      # octubre de 2026" is October 22, not the previous Thursday.
      def self.detect_date(text, today: Date.current)
        return nil if text.blank?

        if (explicit = detect_explicit_date(text, today: today))
          explicit
        elsif text.match?(/\bhoy\b/)
          [ today, 0.95 ]
        elsif text.match?(/\banteayer\b/)
          [ today - 2, 0.85 ]
        elsif text.match?(/\bayer\b/)
          [ today - 1, 0.95 ]
        elsif (weekday = detect_weekday_date(text, today: today))
          weekday
        elsif text.match?(/la semana pasada/i)
          [ today - 7, 0.8 ]
        elsif text.match?(/el mes pasado/i)
          [ today.advance(months: -1), 0.7 ]
        else
          nil
        end
      end

      # Every distinct date a fragment resolves to (relative words + weekdays).
      # Used to flag ambiguous fragments that mention several different dates.
      # When an explicit calendar date exists, weekday words are descriptors of
      # that date instead of independent dates.
      def self.scan_dates(text, today: Date.current)
        return [] if text.blank?

        dates = []
        explicit = parse_explicit_date(text, today: today)
        dates << explicit if explicit
        dates << today - 7 if text.match?(/la semana pasada/i)
        dates << today.advance(months: -1) if text.match?(/el mes pasado/i)
        dates << today if text.match?(/\bhoy\b/)
        dates << today - 2 if text.match?(/\banteayer\b/)
        dates << today - 1 if text.match?(/\bayer\b/)
        unless explicit
          text.scan(WEEKDAY_REGEX).flatten.each do |word|
            dates << weekday_date(word, today)
          end
        end
        dates.uniq
      end

      def self.detect_explicit_date(text, today: Date.current)
        date = parse_explicit_date(text, today: today)
        date ? [ date, 0.95 ] : nil
      end

      # Parses "22 de octubre de 2026", "22 de octubre" (current year) and
      # "22/10/2026" / "22-10-2026". Case and accent insensitive.
      def self.parse_explicit_date(value, today: Date.current)
        text = Text::Service.normalize_text(value)

        if (match = text.match(TEXTUAL_DATE_REGEX))
          build_date(match[3]&.to_i || today.year, MONTHS[match[2]], match[1].to_i)
        elsif (match = text.match(NUMERIC_DATE_REGEX))
          build_date(expand_year(match[3].to_i), match[2].to_i, match[1].to_i)
        end
      end

      # Replaces dates and times with blanks so their digits are never read as
      # amounts by the OCR/receipt heuristic ("10:38", "22 de octubre de 2026").
      def self.mask_dates_and_times(text)
        masked = text.to_s.gsub(TIME_REGEX, " ")
        masked = masked.gsub(TEXTUAL_DATE_REGEX, " ")
        masked.gsub(NUMERIC_DATE_REGEX, " ")
      end

      def self.build_date(year, month, day)
        return nil unless Date.valid_date?(year, month, day)

        Date.new(year, month, day)
      rescue ArgumentError, TypeError
        nil
      end

      def self.expand_year(year)
        year < 100 ? 2000 + year : year
      end
      private_class_method :build_date, :expand_year

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
