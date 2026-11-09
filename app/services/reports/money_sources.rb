# frozen_string_literal: true

# Reports::MoneySources
# Where spending originates: actual expenses grouped by source type (accounts,
# credit cards, cash and any other source kind) and then by individual source,
# with shares, counts and a lazy drill-down scope per source.
# Transfers and debt payments never appear as spending here.
#
# Methods: call
#
# Example: Reports::MoneySources.new(user: user, filter: filter).call[:groups]
class Reports::MoneySources < Reports::Base
  # Payment kinds are bucketed into the three user-facing groups of the
  # report. Loan and pocket spending is still surfaced if historical data
  # contains it, so no real expense is ever dropped from the totals.
  GROUP_BY_KIND = {
    "account" => "accounts",
    "debit_card" => "accounts",
    "wallet" => "accounts",
    "credit_card" => "credit_cards",
    "cash" => "cash",
    "loan" => "loans",
    "pocket" => "pockets"
  }.freeze
  GROUP_KEYS = GROUP_BY_KIND.values.uniq.freeze

  def initialize(user:, filter:, source_kind: nil)
    super(user: user, filter: filter)
    @source_kind = source_kind.to_s.presence_in(GROUP_KEYS)
  end

  def call
    rows = spending_rows(period.range)
    grand_total = rows.sum { |row| row[:total] }
    groups = build_groups(rows, grand_total)

    {
      period: period,
      total: grand_total,
      total_transactions: rows.sum { |row| row[:count] },
      sources_count: rows.size,
      top_group: groups.first,
      groups: groups
    }
  end

  private

  # One grouped query for every kind/source pair, aggregated in memory into
  # the report groups. Avoids per-kind queries for totals and shares.
  def spending_rows(range)
    base = actual_expenses(range)
    scope = base.joins(:money_source).where(money_sources: { user_id: user.id })
    scope = scope.where(money_sources: { kind: kinds_for_source_kind }) if @source_kind

    scope.group("money_sources.kind", "money_sources.id", "money_sources.name")
         .pluck(Arel.sql("money_sources.kind"), Arel.sql("money_sources.id"),
                Arel.sql("money_sources.name"), Arel.sql("ABS(SUM(transactions.amount))"),
                Arel.sql("COUNT(*)"))
         .map do |kind, id, name, total, count|
      { kind: kind, id: id, name: name, total: total.to_d, count: count.to_i, base: base }
    end
  end

  def kinds_for_source_kind
    GROUP_BY_KIND.select { |_kind, group| group == @source_kind }.keys
  end

  def build_groups(rows, grand_total)
    rows.group_by { |row| group_key(row[:kind]) }
        .map do |key, grouped_rows|
      group_total = grouped_rows.sum { |row| row[:total] }
      {
        key: key,
        total: group_total,
        count: grouped_rows.sum { |row| row[:count] },
        share_pct: share_pct(group_total, grand_total),
        sources: source_rows(grouped_rows, group_total)
      }
    end
        .sort_by { |group| -group[:total] }
  end

  def group_key(kind)
    GROUP_BY_KIND.fetch(kind, "other")
  end

  def source_rows(grouped_rows, group_total)
    grouped_rows.sort_by { |row| -row[:total] }.map do |row|
      source_id = row[:id]
      base = row[:base]
      {
        id: source_id,
        name: row[:name],
        total: row[:total],
        count: row[:count],
        share_pct: share_pct(row[:total], group_total),
        scope: -> { base.where(money_source_id: source_id) }
      }
    end
  end

  def share_pct(part, total)
    return nil if total.to_d.zero?

    (part / total * 100).round(1)
  end
end
