# frozen_string_literal: true

# Reports::TimeBuckets
# Shared day/week/month bucketing for report series, so every chart groups
# and zero-fills dates with the same rules.
#
# Methods: bucket_sql, bucket_dates, bucket_label, grouped_totals
#
# Example: include Reports::TimeBuckets and define bucket -> :week
module Reports::TimeBuckets
  BUCKET_LABELS = {
    day: "%d/%m/%Y", week: "%d/%m/%Y", month: "%b"
  }.freeze

  private

  def bucket_label(date)
    I18n.l(date, format: bucket_label_format)
  end

  def bucket_label_format
    BUCKET_LABELS[bucket]
  end

  def bucket_sql
    case bucket
    when :day then "transactions.date"
    when :week then week_bucket_sql
    else "date_trunc('month', transactions.date)"
    end
  end

  # Report series can align weeks to the calendar or to the start of the
  # selected period; a nil origin keeps the calendar-week behavior.
  def week_bucket_sql
    origin = week_origin
    return "date_trunc('week', transactions.date)" unless origin

    "transactions.date - ((transactions.date - DATE '#{origin.iso8601}') % 7)"
  end

  def week_origin
    nil
  end

  def bucket_dates
    case bucket
    when :day then period.range.to_a
    when :week then week_starts
    else month_starts
    end
  end

  def grouped_totals(scope)
    scope.group(bucket_sql)
         .pluck(Arel.sql(bucket_sql), Arel.sql("ABS(SUM(transactions.amount))"))
         .to_h { |date, total| [ date.to_date, total.to_d ] }
  end

  def week_starts
    starts = [ week_origin || period.range.first.beginning_of_week(:monday) ]
    while (next_start = starts.last + 7.days) <= period.range.last
      starts << next_start
    end
    starts
  end

  def month_starts
    starts = [ period.range.first.beginning_of_month ]
    last = period.range.last.beginning_of_month
    while (next_start = starts.last.next_month) <= last
      starts << next_start
    end
    starts
  end
end
