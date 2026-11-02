module PaymentEngine
  # Structured billing period. Months and years use calendar arithmetic so that
  # 28/29/30/31-day months and leap years are respected. End-of-month policy:
  # ActiveSupport clamps the day of month (Jan 31 + 1 month = Feb 28/29) and the
  # following period starts from that clamped date.
  class Duration
    INTERVALS = %w[day month year].freeze

    attr_reader :interval, :count

    def initialize(interval:, count: 1)
      @interval = interval.to_s
      @count = Integer(count)

      raise ArgumentError, "Unsupported interval: #{@interval}" unless INTERVALS.include?(@interval)
      raise ArgumentError, "count must be greater than zero" unless @count.positive?
    end

    def self.from(value)
      return value if value.is_a?(self)

      attributes = value.respond_to?(:symbolize_keys) ? value.symbolize_keys : {}
      new(interval: attributes.fetch(:interval), count: attributes.fetch(:count, 1))
    end

    def days?
      interval == "day"
    end

    def months?
      interval == "month"
    end

    def years?
      interval == "year"
    end

    def apply_to(time)
      case interval
      when "day" then time + count.days
      when "month" then time.advance(months: count)
      when "year" then time.advance(years: count)
      end
    end
    alias from apply_to

    def to_h
      { "interval" => interval, "count" => count }
    end

    def to_s
      "#{count} #{interval}#{'s' unless count == 1}"
    end

    def ==(other)
      other.is_a?(self.class) && other.interval == interval && other.count == count
    end
    alias eql? ==

    def hash
      [ self.class, interval, count ].hash
    end
  end
end
