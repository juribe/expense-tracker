module PaymentEngine
  # Internal domain events published after the surrounding transaction commits.
  # Host applications subscribe with PaymentEngine.on(:membership_activated) { |event| ... }.
  # A failing host callback is logged and never rolls back a confirmed payment.
  module Events
    NAMES = %i[
      membership_activated
      membership_expired
      membership_renewed
      membership_canceled
      subscription_created
      subscription_renewed
      subscription_payment_failed
      subscription_canceled
      payment_approved
      payment_rejected
      payment_refunded
    ].freeze

    class Event
      attr_reader :name, :payload, :occurred_at

      def initialize(name:, payload:, occurred_at: Time.current)
        @name = name.to_sym
        @payload = payload
        @occurred_at = occurred_at
      end

      def [](key)
        payload[key]
      end
    end

    class << self
      def on(name, &block)
        raise ArgumentError, "Unknown PaymentEngine event: #{name}" unless NAMES.include?(name.to_sym)

        callbacks[name.to_sym] << block
        block
      end

      def publish(name, **payload)
        event_name = name.to_sym
        event = Event.new(name: event_name, payload: payload)

        ActiveSupport::Notifications.instrument("payment_engine.#{event_name}", payload)
        callbacks[event_name].each { |callback| invoke(callback, event) }

        event
      end

      # Defers publication until the outermost transaction commits, so host
      # callbacks never observe uncommitted financial state. Runs immediately
      # when no transaction is open.
      def publish_after_commit(name, **payload)
        ActiveRecord.after_all_transactions_commit { publish(name, **payload) }
      end

      def callbacks
        @callbacks ||= Hash.new { |hash, key| hash[key] = [] }
      end

      def reset!
        @callbacks = Hash.new { |hash, key| hash[key] = [] }
      end

      private

      def invoke(callback, event)
        callback.call(event)
      rescue StandardError => error
        PaymentEngine.configuration.engine_logger.error(
          "PaymentEngine callback for #{event.name} failed: #{error.class}"
        )
      end
    end
  end
end
