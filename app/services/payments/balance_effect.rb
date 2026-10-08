# frozen_string_literal: true

module Payments
  # Moves a payment's principal component against its debt balance.
  # The full amount never touches the balance — only what was recorded as
  # principal reduces debt and frees credit. Loan payments with principal
  # auto-increment installments_paid (and reverse it when the payment goes
  # away or becomes interest-only). Card payments skip the adjustment when
  # the expense was paid from the same card: the money never left that source.
  #
  #   Payments::BalanceEffect.play!(payment)
  #   Payments::BalanceEffect.play!(payment, previous_principal: 900_000)
  class BalanceEffect
    def self.play!(payment, previous_principal: 0)
      new(payment, previous_principal: previous_principal).play!
    end

    def initialize(payment, previous_principal: 0)
      @payment = payment
      @previous_principal = previous_principal.to_d
    end

    def play!
      if destroyed?
        reverse_loan if loan?
        reverse_card if credit_card?
        return
      end

      # A revolving line has no schedule: its payments move the debt but
      # never fake installment progress in either direction.
      counts_installment = principal.positive? && !revolving_target?
      had_installment = @previous_principal.positive?
      delta = principal - @previous_principal

      apply_loan(delta, counts_installment, had_installment) if loan?
      apply_card(delta) if credit_card?
    end

    private

    attr_reader :payment

    def destroyed?
      payment.destroyed?
    end

    def principal
      payment.principal_amount.to_d
    end

    def loan?
      payment.money_source.loan?
    end

    def credit_card?
      payment.money_source.credit_card?
    end

    def revolving_target?
      payment.money_source.revolving?
    end

    def apply_loan(delta, counts_installment, had_installment)
      credit_account = payment.money_source.credit_account
      return if credit_account.nil?

      if delta.nonzero?
        outstanding = credit_account.outstanding_balance.to_d
        credit_account.update_column(:outstanding_balance, [ outstanding - delta, 0.to_d ].max)
      end

      # Only payments with principal count as installments, and each payment
      # is counted at most once — symmetric between apply and reversal.
      adjust_installments(credit_account, 1) if counts_installment && !had_installment
      adjust_installments(credit_account, -1) if !counts_installment && had_installment
    end

    def adjust_installments(credit_account, delta)
      counted = credit_account.installments_paid.to_i
      credit_account.update_column(:installments_paid, [ counted + delta, 0 ].max)
    end

    def reverse_loan
      credit_account = payment.money_source.credit_account
      return if credit_account.nil?

      outstanding = credit_account.outstanding_balance.to_d
      credit_account.update_column(:outstanding_balance, outstanding + @previous_principal)

      # Interest-only payments were never counted, so they never uncount;
      # revolving targets were never counted in the first place.
      adjust_installments(credit_account, -1) if @previous_principal.positive? && !revolving_target?
      @previous_principal = principal
    end

    def apply_card(delta)
      return if delta.zero? || paid_from_same_source?

      MoneySources::BalanceSync.adjust!(payment.money_source, delta)
    end

    def reverse_card
      return if paid_from_same_source?

      MoneySources::BalanceSync.adjust!(payment.money_source, -@previous_principal)
    end

    def paid_from_same_source?
      payment.expense_money_source_id == payment.money_source_id
    end
  end
end
