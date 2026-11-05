# frozen_string_literal: true

module FinancialHabits
  module AnalysisState
    LOCK_TTL = 60.seconds
    STATE_TTL = 1.day
    STALE_PENDING = 5.minutes

    class << self
      attr_writer :cache

      def read(user_id)
        payload = cache.read(state_key(user_id))
        return "idle" unless payload.is_a?(Hash)

        state = payload.with_indifferent_access[:state].presence || "idle"
        return "failed" if state == "pending" && stale?(payload)

        state
      end

      def write(user_id, state)
        cache.write(
          state_key(user_id),
          { "state" => state.to_s, "at" => Time.current.iso8601 },
          expires_in: STATE_TTL
        )
      end

      def acquire_lock(user_id)
        cache.write(lock_key(user_id), true, unless_exist: true, expires_in: LOCK_TTL)
      end

      def state_key(user_id)
        "financial_habits:state:#{user_id}"
      end

      def lock_key(user_id)
        "financial_habits:lock:#{user_id}"
      end

      def cache
        @cache ||= SharedCache.store
      end

      private

      def stale?(payload)
        raw_timestamp = payload.with_indifferent_access[:at]
        return false if raw_timestamp.blank?

        timestamp = Time.zone.parse(raw_timestamp.to_s)
        return false if timestamp.nil?

        timestamp < STALE_PENDING.ago
      rescue ArgumentError, TypeError
        false
      end
    end
  end
end