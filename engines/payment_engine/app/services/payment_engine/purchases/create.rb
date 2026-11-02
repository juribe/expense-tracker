module PaymentEngine
  module Purchases
    # Creates a purchase and initializes the provider checkout flow.
    # This service never activates a membership: activation happens only after a
    # confirmed payment (webhook or authorized administrative confirmation) or
    # through an authorized free trial.
    class Create
      def self.call(owner:, payment_option:, provider: nil, description: nil, metadata: {})
        new(owner: owner, payment_option: payment_option, provider: provider,
            description: description, metadata: metadata).call
      end

      def initialize(owner:, payment_option:, provider: nil, description: nil, metadata: {})
        @owner = owner
        @payment_option = payment_option
        @requested_provider = provider
        @description = description
        @metadata = metadata.to_h
      end

      def call
        validation = validate
        return validation if validation

        provider_adapter = PaymentEngine.provider(provider_name)
        capability = capability_error(provider_adapter)
        return capability if capability

        purchase = nil
        payment = nil
        duplicate = nil

        Purchase.transaction do
          with_purchase_lock do
            duplicate = duplicate_purchase
            raise ActiveRecord::Rollback if duplicate

            purchase = Purchase.create!(
              owner: owner,
              payment_option: payment_option,
              provider: provider_adapter.name,
              status: "pending",
              description: description || payment_option.name,
              metadata: metadata
            )
            payment = purchase.payments.create!(
              provider: provider_adapter.name,
              amount: purchase.amount,
              currency: purchase.currency,
              status: "pending"
            )
          end
        end

        return duplicate_error(duplicate) if duplicate

        response = provider_adapter.create_payment(
          purchase: purchase,
          payment: payment,
          customer: nil
        )
        response_data = response.data.to_h

        if response.success?
          payment.update!(
            provider_transaction_id: response_data[:provider_transaction_id].presence || payment.provider_transaction_id,
            metadata: payment.metadata.merge(response_data[:metadata].to_h)
          )
          Result.success(data: { purchase: purchase, payment: payment, checkout: response_data[:checkout] })
        else
          mark_provider_failure(purchase, payment, response)
        end
      rescue UnknownProviderError, ConfigurationError => error
        Result.failure(code: :provider_not_configured, errors: [ error.message ])
      rescue ActiveRecord::RecordInvalid => error
        Result.failure(code: :invalid_record, errors: error.record.errors.full_messages)
      rescue StandardError => error
        PaymentEngine.configuration.engine_logger.error("PaymentEngine purchase failed: #{error.class}")
        Result.failure(code: :provider_error, errors: [ "the payment provider could not start the purchase" ])
      end

      private

      attr_reader :owner, :payment_option, :description, :metadata

      def provider_name
        (@requested_provider || PaymentEngine.configuration.default_provider).presence&.to_sym
      end

      def validate
        if owner.blank? || !owner.respond_to?(:persisted?) || !owner.persisted?
          return failure(:invalid_owner, "owner must be a persisted host record")
        end
        return failure(:invalid_option, "payment option is required") if payment_option.blank?
        unless payment_option.active?
          return failure(:inactive_option, "payment option is not available for new purchases")
        end
        unless payment_option.membership_type.active?
          return failure(:inactive_membership_type, "membership type is not available for new purchases")
        end

        nil
      end

      def capability_error(provider_adapter)
        return failure(:unsupported_operation, "#{provider_adapter.name} does not support payments") unless provider_adapter.supports?(:payments)
        return unless payment_option.recurring?

        failure(:unsupported_operation, "#{provider_adapter.name} does not support recurring payments") unless provider_adapter.supports?(:recurring_payments)
      end

      def duplicate_purchase
        return if duplicate_window.zero?

        Purchase.for_owner(owner)
          .where(payment_option: payment_option, status: %w[pending processing])
          .where("created_at >= ?", duplicate_window.ago)
          .order(:id)
          .first
      end

      def duplicate_window
        PaymentEngine.configuration.purchase_duplicate_window_minutes.to_i.minutes
      end

      def duplicate_error(existing)
        Result.failure(
          code: :duplicate_purchase,
          errors: [ "a purchase for this option is already in progress" ],
          data: { purchase: existing }
        )
      end

      def mark_provider_failure(purchase, payment, response)
        Purchase.transaction do
          purchase.update!(status: "failed")
          payment.update!(status: "rejected", failure_reason: response.error_message)
        end

        Result.failure(
          code: response.code || :provider_error,
          errors: response.errors,
          data: { purchase: purchase, payment: payment }
        )
      end

      def with_purchase_lock
        return yield unless ActiveRecord::Base.connection.adapter_name.match?(/postgres/i)

        key = "payment_engine_purchase:#{owner.class.polymorphic_name}:#{owner.id}:#{payment_option.id}"
        ActiveRecord::Base.connection.execute(
          ActiveRecord::Base.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(hashtext(?))", key ])
        )
        yield
      end

      def failure(code, message)
        Result.failure(code: code, errors: [ message ])
      end
    end
  end
end
