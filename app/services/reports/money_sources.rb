# frozen_string_literal: true

# Reports::MoneySources
# Where spending originates: actual expenses grouped by money source kind and
# then by source, with shares, counts and a lazy drill-down scope per source.
# Transfers and debt payments never appear as spending here.
#
# Methods: call
#
# Example: Reports::MoneySources.new(user: user, filter: filter).call[:kinds]
class Reports::MoneySources < Reports::Base
  def call
    kinds = grouped(period.range)
    grand_total = kinds.sum { |_, row| row[:total] }

    {
      period: period,
      total: grand_total,
      kinds: kinds.sort_by { |_, row| -row[:total] }
                  .map { |kind, row| kind_row(kind, row, grand_total) }
    }
  end

  private

  def grouped(range)
    base = filter.expense_scope(range).where.missing(:payments)
    source_ids = user.money_sources.ids
    base.joins(:money_source)
        .where(money_sources: { id: source_ids })
        .group("money_sources.kind")
        .pluck(Arel.sql("money_sources.kind"), Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
        .index_by { |kind, _total, _count| kind }
        .transform_values do |kind, total, count|
      { kind: kind, total: total.to_d, count: count.to_i, base: base }
    end
  end

  def kind_row(kind, row, grand_total)
    sources = source_rows(kind, row[:base])
    {
      kind: kind,
      kind_label: I18n.t("kinds.#{kind}", default: kind.titleize),
      total: row[:total], count: row[:count],
      share_pct: share_pct(row[:total], grand_total),
      sources: sources
    }
  end

  def source_rows(kind, base)
    base.joins(:money_source)
        .where(money_sources: { kind: kind })
        .group("money_sources.id", "money_sources.name")
        .pluck(Arel.sql("money_sources.id"), Arel.sql("money_sources.name"),
               Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
        .sort_by { |_id, _name, total, _count| -total }
        .map do |id, name, total, count|
      {
        id: id, name: name, total: total.to_d, count: count.to_i,
        share_pct: share_pct(total.to_d, kind_total(base, kind)),
        scope: -> { base.where(money_source_id: id) }
      }
    end
  end

  def kind_total(base, kind)
    base.joins(:money_source)
        .where(money_sources: { kind: kind })
        .sum(Arel.sql("ABS(transactions.amount)"))
  end

  def share_pct(part, total)
    return nil if total.to_d.zero?

    (part / total * 100).round(1)
  end
end
