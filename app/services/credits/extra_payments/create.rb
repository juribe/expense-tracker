# frozen_string_literal: true

module Credits
  module ExtraPayments
    # Create
    # Records a REAL extraordinary payment: a cash Expense leaves the chosen
    # funding money source (account/card/wallet) and the payment is applied
    # to the debt through the standard store machinery
    # (Payments::Apply → Payments::BalanceEffect), so the loan's real
    # balance moves and the payment shows up in the loan's payment list,
    # reports and Día de Cuadre.
    #
    #   reduce_term / reduce_installment → the applied amount is pure capital
    #   prepay_installments            → covers the ruled installments at
    #     face value: the distribution carries their capital/interest/
    #     insurance and the leftover as "other"
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
          money_source: @funding_money_source
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
