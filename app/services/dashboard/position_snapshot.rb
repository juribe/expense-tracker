# frozen_string_literal: true

# Dashboard::PositionSnapshot
# Read-only money position for the dashboard KPI cards: liquid balances,
# savings pockets, unused credit and the two debt buckets (credit cards vs.
# every loan, revolving lines included). Reads cached balances and credit
# accounts only — no aggregation over the transactions table.
#
# Methods: call
#
# Example: Dashboard::PositionSnapshot.call(user: user)[:credit_debt]
class Dashboard::PositionSnapshot
  # Kinds that hold spendable money: the card's "Dinero en cuentas" total.
  LIQUID_KINDS = %w[account debit_card cash wallet].freeze

  def self.call(user:)
    new(user: user).call
  end

  def initialize(user:)
    @user = user
  end

  def call
    {
      accounts_balance: accounts_balance,
      savings_balance: savings_balance,
      credit_available: credit_available,
      credit_debt: credit_debt,
      loan_debt: loan_debt
    }
  end

  private

  def sources
    @sources ||= @user.money_sources.includes(:credit_account)
  end

  def accounts_balance
    sources.select { |source| LIQUID_KINDS.include?(source.kind) }.sum(&:balance)
  end

  def savings_balance
    sources.select(&:pocket?).sum(&:balance)
  end

  # A card or a revolving line: both draw from a credit limit (cupo). Only
  # cards count as "Deuda TC"; every loan counts as "Deudas normales".
  def credit_lines
    sources.select { |source| source.credit_card? || source.revolving? }
  end

  def credit_available
    credit_lines.filter_map(&:available_credit).sum
  end

  def credit_debt
    sources.select(&:credit_card?).sum(&:used_credit)
  end

  # Owed on every loan — revolving lines included. The stored outstanding
  # balance is used when present, falling back to the negative money-source
  # balance when the credit account row is missing.
  def loan_debt
    sources.select(&:loan?)
           .sum { |source| source.outstanding_balance&.to_d || [ -source.balance, 0 ].max }
  end
end
