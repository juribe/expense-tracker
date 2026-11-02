module PaymentEngine
  module Subscriptions
    # Creates the recurring agreement with the provider. The membership period is
    # defined by the paid purchase; this service only records the renewal
    # mechanism and never charges the owner by itself.
    class Create
      def self.call(membership:, payment_option: nil, provider: nil, provider_subscription_id: nil,
                    status: "active", starts_at: nil, ends_at: nil, next_billing_at: nil,
                    trial_ends_at: nil, metadata: {})
        new(
          membership: membership,
          payment_option: payment_option,
          provider: provider,
          provider_subscription_id: provider_subscription_id,
          status: status,
          starts_at: starts_at,
          ends_at: ends_at,
          next_billing_at: next_billing_at,
          trial_ends_at: trial_ends_at,
          metadata: metadata
        ).call
      end

      def initialize(membership:, payment_option: nil, provider: nil, provider_subscription_id: nil,
                     status: "active", starts_at: nil, ends_at: nil, next_billing_at: nil,
                     trial_ends_at: nil, metadata: {})
        @membership = membership
        @payment_option = payment_option
        @requested_provider = provider
        @provider_subscription_id = provider_subscription_id
        @status = status
        @starts_at = starts_at
        @ends_at = ends_at
        @next_billing_at = next_billing_at
        @trial_ends_at = trial_ends_at
        @metadata = metadata.to_h
      end

      def call
        return Result.failure(code: :invalid_membership, errors: [ "membership is required" ]) if membership.blank?
        return Result.failure(code: :invalid_option, errors: [ "payment option is required" ]) if option.blank?
        return Result.failure(code: :provider_not_configured, errors: [ "no payment provider configured" ]) if provider_name.blank?

        existing = find_existing
        return Result.success(data: existing, code: :already_exists) if existing

        subscription = build_subscription

        unless provider_subscription_id.present?
          adapter = PaymentEngine.provider(provider_name)
          unless adapter.supports?(:recurring_payments)
            return Result.failure(code: :unsupported_operation,
                                  errors: [ "#{adapter.name} does not support recurring subscriptions" ])
          end

          response = adapter.create_subscription(subscription: subscription)
          return response unless response.success?

          subscription.provider_subscription_id = response.data.to_h[:provider_subscription_id]
        end

        subscription.save!
        Events.publish_after_commit(:subscription_created, subscription: subscription, membership: membership)
        Result.success(data: subscription)
      rescue ActiveRecord::RecordNotUnique
        Result.success(data: find_existing, code: :already_exists)
      rescue ActiveRecord::RecordInvalid => error
        Result.failure(code: :invalid_record, errors: error.record.errors.full_messages)
      end

      private

      attr_reader :membership, :payment_option, :provider_subscription_id, :status,
                  :starts_at, :ends_at, :next_billing_at, :trial_ends_at, :metadata

      def option
        payment_option || membership.payment_option
      end

      def provider_name
        (@requested_provider || PaymentEngine.configuration.default_provider).presence&.to_sym
      end

      def period_start
        starts_at || membership.starts_at || PaymentEngine.current_time
      end

      def period_end
        ends_at || option.duration.apply_to(period_start)
      end

      def find_existing
        return if provider_subscription_id.blank?

        Subscription.find_by(provider: provider_name.to_s, provider_subscription_id: provider_subscription_id)
      end

      def build_subscription
        Subscription.new(
          membership: membership,
          payment_option: option,
          provider: provider_name.to_s,
          provider_subscription_id: provider_subscription_id,
          status: status,
          current_period_starts_at: period_start,
          current_period_ends_at: period_end,
          next_billing_at: next_billing_at || period_end,
          trial_ends_at: trial_ends_at,
          metadata: metadata
        )
      end
    end
  end
end
