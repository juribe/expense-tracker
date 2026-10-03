# frozen_string_literal: true

# Reports::Transfers
# Money movements between sources, grouped by route (origin → destination)
# with totals, counts and the movement's nature: debt payment when the
# destination is a credit card or loan, disbursement when the origin is a
# loan, internal otherwise.
#
# Methods: call
#
# Example: Reports::Transfers.new(user: user, filter: filter).call[:routes]
class Reports::Transfers < Reports::Base
  def call
    routes = grouped(period.range).sort_by { |row| -row[:total] }

    {
      period: period,
      total: routes.sum { |row| row[:total] },
      count: routes.sum { |row| row[:count] },
      routes: routes.map { |row| route_row(row) }
    }
  end

  private

  def grouped(range)
    Transfer.for_user(user)
            .where(date: range)
            .group(:from_source_id, :to_source_id)
            .pluck(Arel.sql("transfers.from_source_id"), Arel.sql("transfers.to_source_id"),
                   Arel.sql("SUM(transfers.amount)"), Arel.sql("COUNT(*)"),
                   Arel.sql("MIN(transfers.date)"), Arel.sql("MAX(transfers.date)"))
            .map do |from_id, to_id, total, count, first, last|
      { from_id: from_id, to_id: to_id, total: total.to_d, count: count.to_i,
        first_date: first, last_date: last }
    end
  end

  def route_row(row)
    from = MoneySource.find_by(id: row[:from_id])
    to = MoneySource.find_by(id: row[:to_id])
    row.merge(
      from_name: from&.name, to_name: to&.name,
      movement: movement_of(from, to)
    )
  end

  def movement_of(from, to)
    return :disbursement if from&.loan?
    return :debt_payment if to&.debt_payment_target?

    :internal
  end
end
