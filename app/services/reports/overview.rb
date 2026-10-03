# frozen_string_literal: true

# Reports::Overview
# Main report dashboard: income, actual spending, debt payments, transfers and
# net cash flow for the selected period, with previous equivalent period
# comparisons. Structured hash shared by the view and, later, Financial Chat.
#
# Methods: call
#
# Example: Reports::Overview.new(user: user, filter: filter).call[:expenses][:total]
class Reports::Overview < Reports::Base
  def call
    {
      period: period,
      income: income_section,
      expenses: expenses_section,
      debt: debt_section,
      transfers: transfers_section,
      net_cash_flow: net_cash_flow
    }
  end

  private

  def income_section
    total = filter.income_scope(period.range).sum(:amount)
    previous = filter.income_scope(period.previous_range).sum(:amount)
    {
      total: total, previous: previous, delta_pct: delta_pct(total, previous), count: filter.income_scope(period.range).count
    }
  end

  def expenses_section
    actual = aggregate_actual(period.range)
    previous = aggregate_actual(period.previous_range)
    {
      total: actual[:total], previous: previous[:total], delta_pct: delta_pct(actual[:total], previous[:total]),
      count: actual[:count], average: actual[:count].positive? ? actual[:total] / actual[:count] : nil
    }
  end

  def debt_section
    current = debt_totals(period.range)
    previous = debt_totals(period.previous_range)
    {
      total: current[:total], previous: previous[:total], delta_pct: delta_pct(current[:total], previous[:total]),
      principal: current[:principal], interest: current[:interest],
      insurance: current[:insurance], other: current[:other], count: current[:count]
    }
  end

  def transfers_section
    {
      total: filter.transfer_scope(period.range).sum(:amount),
      count: filter.transfer_scope(period.range).count
    }
  end

  def net_cash_flow
    income_section[:total] - expenses_section[:total] - debt_section[:total]
  end

  def aggregate_actual(range)
    total, count = filter.expense_scope(range).where.missing(:payments)
                         .pick(Arel.sql("ABS(SUM(transactions.amount))"), Arel.sql("COUNT(*)"))
    { total: total.to_d, count: count.to_i }
  end

  def debt_totals(range)
    components = Payment.for_user(user)
                        .where(date: range)
                        .where("exists (?)", filter.expense_scope(range).select(:id))
                        .pick(
                          Arel.sql("COALESCE(SUM(amount), 0)"),
                          Arel.sql("COALESCE(SUM(principal_amount), 0)"),
                          Arel.sql("COALESCE(SUM(interest_amount), 0)"),
                          Arel.sql("COALESCE(SUM(insurance_amount), 0)"),
                          Arel.sql("COALESCE(SUM(other_amount), 0)"),
                          Arel.sql("COUNT(*)")
                        ) || [ 0.to_d, 0.to_d, 0.to_d, 0.to_d, 0.to_d, 0 ]

    amount, principal, interest, insurance, other, count = components
    transferred = transferred_to_debt(range)
    count += 1 if transferred.positive?
    { total: amount + transferred, principal: principal.to_d,
      interest: interest.to_d, insurance: insurance.to_d, other: other.to_d, count: count.to_i }
  end

  # A transfer into a credit card or loan IS that debt's payment in this app's
  # model (TransfersController source-pool rules), so it joins the debt total.
  # Transfers out of a loan are disbursements, never repayments.
  def transferred_to_debt(range)
    filter.transfer_scope(range)
          .where("to_source_id IN (?)", MoneySource.debt_payment_targets.select(:id))
          .where("from_source_id NOT IN (?)", MoneySource.debt_payment_targets.select(:id))
          .sum(:amount)
  end

  def delta_pct(current, previous)
    self.class.delta_pct(current, previous)
  end
end
