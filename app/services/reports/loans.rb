# frozen_string_literal: true

# Reports::Loans
# Debt overview per loan plus a consolidated view: outstanding balance,
# installment, period's principal/interest/insurance paid (from Payment
# components and transfers into the loan), rates and next payment date.
#
# Methods: call
#
# Example: Reports::Loans.new(user: user, filter: filter).call[:total_debt]
class Reports::Loans < Reports::Base
  def call
    loans = loan_sources
    payments = grouped_payments(period.range)
    transfers = grouped_transfers(period.range)
    rows = loans.map { |loan| loan_row(loan, payments, transfers) }

    {
      period: period,
      rows: rows,
      total_debt: rows.sum { |row| row[:balance].to_d },
      principal_paid: rows.sum { |row| row[:principal_paid] },
      interest_paid: rows.sum { |row| row[:interest_paid] },
      insurance_paid: rows.sum { |row| row[:insurance_paid] },
      total_paid: rows.sum { |row| row[:paid] },
      total_payments_count: rows.sum { |row| row[:payments_count] }
    }
  end

  private

  def loan_sources
    scope = user.money_sources.active.where(kind: "loan").includes(:credit_account)
    scope = scope.where(id: filter.active_source_id) if filter.active_source_id
    scope
  end

  def loan_row(loan, payments, transfers)
    paid = payments.fetch(loan.id, empty_components)
    transferred = transfers.fetch(loan.id, 0.to_d)
    {
      id: loan.id, name: loan.name, sub_kind: loan.sub_kind,
      balance: loan.outstanding_balance&.to_d,
      installment_amount: loan.installment_amount&.to_d,
      installment_count: loan.installment_count,
      remaining_installments: loan.remaining_installments,
      interest_rate: loan.interest_rate,
      interest_rate_label: loan.interest_rate_label,
      principal_amount: loan.principal_amount&.to_d,
      paid: paid[:amount] + transferred,
      principal_paid: paid[:principal] + transferred,
      interest_paid: paid[:interest],
      insurance_paid: paid[:insurance],
      other_paid: paid[:other],
      payments_count: paid[:count] + (transferred.positive? ? 1 : 0),
      next_payment_date: Loans::NextPayment.call(loan)
    }
  end

  def grouped_payments(range)
    Payment.for_user(user)
           .where(money_source_id: loan_ids, date: range)
           .group(:money_source_id)
           .pluck(Arel.sql("payments.money_source_id"),
                  Arel.sql("SUM(payments.amount)"),
                  Arel.sql("SUM(payments.principal_amount)"),
                  Arel.sql("SUM(payments.interest_amount)"),
                  Arel.sql("SUM(payments.insurance_amount)"),
                  Arel.sql("SUM(payments.other_amount)"),
                  Arel.sql("COUNT(*)"))
           .to_h do |source_id, amount, principal, interest, insurance, other, count|
      [ source_id, { amount: amount.to_d, principal: principal.to_d, interest: interest.to_d,
                     insurance: insurance.to_d, other: other.to_d, count: count.to_i } ]
    end
  end

  # A transfer into a loan IS that loan's payment; transfers out of a loan are
  # disbursements and never counted here.
  def grouped_transfers(range)
    Transfer.for_user(user)
            .where(date: range)
            .where("from_source_id NOT IN (?)", MoneySource.debt_payment_targets.select(:id))
            .group(:to_source_id)
            .sum(:amount)
            .transform_values(&:to_d)
  end

  def loan_ids
    loan_sources.map(&:id)
  end

  def empty_components
    { amount: 0.to_d, principal: 0.to_d, interest: 0.to_d, insurance: 0.to_d, other: 0.to_d, count: 0 }
  end
end
