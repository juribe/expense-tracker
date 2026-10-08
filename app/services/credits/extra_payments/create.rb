# frozen_string_literal: true

module Credits
  module ExtraPayments
    # Create
    # Records a REAL extraordinary payment.
    #
    # Amortizing credit: a cash Expense leaves the chosen funding money
    # source and the payment is applied to the debt through the standard
    # store machinery (Payments::Apply → Payments::BalanceEffect), so the
    # loan's real balance moves and the payment shows up in the loan's
    # payment list, reports and Día de Cuadre.
    #
    #   reduce_term / reduce_installment → the applied amount is pure capital
    #   prepay_installments            → covers the ruled installments at
    #     face value: the distribution carries their capital/interest/
    #     insurance and the leftover as "other"
    #
    # Revolving credit (credit cards / crédito rotativo, application_type
    # "reduce_balance"): a Transfer from the funding source to the debt —
    # the transfer callbacks move the same balance the rest of the app
    # reads (card cached balance / line outstanding_balance), so credit
    # balance, available credit and utilization all reflect it. No Expense,
    # no schedule, no installments. Overpaying the balance is rejected.
    #
    # Methods: call
    class Create
      def self.call(money_source:, funding_money_source:, date:, amount:, application_type:, note: nil)
        new(money_source, funding_money_source, date, amount, application_type, note).call
      end

      def initialize(money_source, funding_money_source, date, amount, application_type, note)
        @money_source = money_source
        @funding_money_source = funding_money_source
        @date = date
        @amount = amount
        @application_type = application_type
        @note = note
      end

      def call
        return ServiceResult.error([ funding_missing_error ]) if @funding_money_source.nil?

        return record_revolving_payment if @application_type == "reduce_balance"

        projection_result = refresh_projection
        return projection_result if projection_result.failure?

        projection = projection_result.result
        effect = Credits::Simulator.run(projection: projection, strategy: @application_type,
                                        params: { "amount" => @amount.to_s })
        distribution = distribution_for(effect, projection)

        extra = @money_source.credit_extra_payments.build(
          date: @date,
          amount: normalized_amount,
          application_type: @application_type,
          funding_money_source_id: @funding_money_source.id,
          principal_reduction: BigDecimal(distribution[:principal_amount]),
          installments_affected: installments_affected(effect),
          effect: effect.merge("distribution" => distribution),
          note: @note
        )

        payment_result = nil
        ActiveRecord::Base.transaction do
          extra.save!
          payment_result = apply_payment!(distribution)
          raise ActiveRecord::Rollback unless payment_result.success?

          extra.update!(payment_id: payment_result.result.id,
                        expense_id: payment_result.result.expense_id)
        end
        return ServiceResult.error(payment_result.errors) if payment_result.failure?

        ServiceResult.success(extra.reload)
      rescue ActiveRecord::RecordInvalid => e
        ServiceResult.error(e.record.errors.full_messages)
      end

      private

      # Revolving products: the abono is only a balance movement. The
      # Transfer lowers the debt (card cached balance / line outstanding
      # balance) and frees the credit limit; no amortization is touched.
      def record_revolving_payment
        return ServiceResult.error([ not_revolving_error ]) unless revolving_target?

        amount = normalized_amount
        balance = revolving_balance
        return ServiceResult.error([ exceeds_balance_error(balance) ]) if amount > balance

        extra = @money_source.credit_extra_payments.build(
          date: @date,
          amount: amount,
          application_type: "reduce_balance",
          funding_money_source_id: @funding_money_source.id,
          principal_reduction: amount,
          effect: revolving_effect(balance, amount),
          note: @note
        )
        ActiveRecord::Base.transaction do
          extra.save!
          transfer = Transfer.create!(
            user: @money_source.user, from_source: @funding_money_source,
            to_source: @money_source, amount: amount, date: @date,
            note: description
          )
          extra.update!(transfer_id: transfer.id)
        end
        ServiceResult.success(extra.reload)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        ServiceResult.error(e.record.errors.full_messages)
      end

      def revolving_target?
        @money_source.credit_card? || @money_source.revolving?
      end

      # The owed number the rest of the app displays: the card's used credit
      # (-balance) or the line's credit_account.outstanding_balance.
      def revolving_balance
        return @money_source.used_credit.to_d if @money_source.credit_card?

        @money_source.credit_account&.outstanding_balance.to_d
      end

      def revolving_effect(balance, amount)
        {
          "application" => "reduce_balance",
          "balance_before" => balance.to_s("F"),
          "balance_after" => (balance - amount).to_s("F")
        }
      end

      def exceeds_balance_error(balance)
        I18n.t("credits.extras.exceeds_balance", balance: MoneyFormat.number(balance))
      end

      def not_revolving_error
        I18n.t("credits.extras.only_revolving")
      end

      def apply_payment!(distribution)
        Payments::Apply.call(
          user: @money_source.user,
          money_source: @money_source,
          expense: build_expense(distribution_total(distribution)),
          distribution: distribution
        )
      end

      # The expense must match the payment distribution exactly (validation
      # of Payments::Apply), so its amount is what actually pays the credit.
      def distribution_total(distribution)
        [ distribution[:principal_amount], distribution[:interest_amount],
         distribution[:insurance_amount], distribution[:other_amount] ]
          .map(&:to_d).sum
      end

      def build_expense(amount)
        Expense.create!(
          user: @money_source.user,
          amount: amount,
          description: description,
          date: @date,
          kind: "expense",
          source: "manual",
          money_source: @funding_money_source,
          category: payment_category
        )
      end

      # Abonos never invent a category: the expense is a debt payment, so it
      # lands in the same default "Pagos de créditos" category recurring
      # payments share (created on demand, same pattern as db/seeds.rb and
      # the setup wizard).
      def payment_category
        @payment_category ||= Category.find_or_create_by!(
          name: I18n.t("categories.debt_payments"),
          is_default: true,
          category_type: "expense"
        )
      end

      def description
        "#{I18n.t('credits.extras.expense_description', default: 'Abono extraordinario')} — #{@money_source.name}"
      end

      # reduce strategies: the whole (clamped) abono is capital and moves the
      # balance. prepay covers installments at face value: their capital/
      # interest/insurance travel with the payment and the leftover (an
      # incomplete next installment) is recorded as other charges.
      def distribution_for(effect, projection)
        if @application_type == "prepay_installments"
          covered = projection.future_rows.take(effect["installments_covered"].to_i)
          remainder = normalized_amount - covered.sum { |row| row["total_payment"].to_d }
          {
            principal_amount: money(covered.sum { |row| row["principal"].to_d }),
            interest_amount: money(covered.sum { |row| row["interest"].to_d }),
            insurance_amount: money(covered.sum { |row| row["insurance"].to_d }),
            other_amount: money([ remainder, 0 ].max)
          }
        else
          {
            principal_amount: money(applied_amount(effect)),
            interest_amount: "0.0", insurance_amount: "0.0", other_amount: "0.0"
          }
        end
      end

      # What actually goes to capital: clamp the abono to the outstanding
      # balance (a bigger abono only pre-pays installments on a nearly-paid
      # loan).
      def applied_amount(effect)
        balance = effect["balance_before"].to_d
        [ normalized_amount, balance ].min
      rescue NoMethodError, TypeError
        0.to_d
      end

      def installments_affected(effect)
        if @application_type == "prepay_installments"
          effect["installments_covered"].to_i
        else
          effect["installments_eliminated"].to_i
        end
      end

      def money(value)
        value.to_d.round(2).to_s("F")
      end

      def normalized_amount
        BigDecimal(MoneyFormat.normalize(@amount).to_s)
      end

      # The effect must be computed on a projection that matches the current
      # real balance (a previous abono may have moved it). The Builder itself
      # returns the existing projection when it is fresh.
      def refresh_projection
        Credits::Projection::Builder.call(money_source: @money_source)
      end

      def funding_missing_error
        I18n.t("credits.extras.funding_blank", default: "Selecciona la fuente de dinero…")
      end
    end
  end
end
