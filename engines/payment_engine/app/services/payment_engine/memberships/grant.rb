module PaymentEngine
  module Memberships
    # Single entry point for granting access. Creates the membership when the
    # owner has no open access for that type, or extends the existing one.
    #
    # Extension always starts from the later of the current expiration and now,
    # so paying late never shortens access and renewals never restart the period
    # from the webhook reception time.
    class Grant
      MAX_CONFLICT_RETRIES = 2
      UNSET = Object.new.freeze

      def self.call(**arguments)
        new(**arguments).call
      end

      def initialize(owner:, membership_type:, duration: nil, payment_option: nil, membership: nil,
                     starts_at: nil, status: "active", metadata: {}, expires_at: UNSET)
        @owner = owner
        @membership_type = membership_type
        @duration = duration
        @payment_option = payment_option
        @membership = membership
        @starts_at = starts_at
        @status = status
        @metadata = metadata.to_h
        @explicit_expiration = !expires_at.equal?(UNSET)
        @expires_at = @explicit_expiration ? expires_at : nil
        @conflict_attempts = 0
      end

      def call
        return failure("owner is required") if owner.blank?
        return failure("membership type is required") if membership_type.blank?
        return failure("duration or expires_at is required") if duration.blank? && !explicit_expiration?

        granted = nil
        activated = false

        Membership.transaction do
          record = membership || find_open_membership

          if record
            record.lock!
            was_active = record.active?
            extend_record(record)
            activated = !was_active
          else
            record = create_record
            activated = true
          end

          granted = record
        end

        publish_events(granted, activated)
        Result.success(data: granted)
      rescue ActiveRecord::RecordNotUnique => error
        @conflict_attempts += 1
        retry if @conflict_attempts < MAX_CONFLICT_RETRIES

        Result.failure(code: :membership_conflict, errors: [ error.message ])
      rescue ActiveRecord::RecordInvalid => error
        Result.failure(code: :membership_conflict, errors: error.record.errors.full_messages)
      end

      private

      attr_reader :owner, :membership_type, :duration, :payment_option,
                  :membership, :starts_at, :status, :metadata, :expires_at

      def explicit_expiration?
        @explicit_expiration
      end

      def find_open_membership
        Membership.for_owner(owner)
          .where(membership_type: membership_type)
          .where(status: Membership::ACCESS_STATUSES)
          .lock
          .first
      end

      def create_record
        start_time = starts_at || PaymentEngine.current_time
        Membership.create!(
          owner: owner,
          membership_type: membership_type,
          payment_option: payment_option,
          status: status,
          starts_at: start_time,
          expires_at: explicit_expiration? ? expires_at : duration.apply_to(start_time),
          metadata: metadata
        )
      end

      def extend_record(record)
        start_time = starts_at || PaymentEngine.current_time
        base = record.expires_at || start_time
        base = start_time if base < start_time

        record.assign_attributes(
          status: "active",
          expires_at: explicit_expiration? ? expires_at : duration.apply_to(base),
          canceled_at: nil,
          payment_option: payment_option || record.payment_option,
          metadata: record.metadata.merge(metadata)
        )
        record.save!
      end

      def publish_events(record, activated)
        event = activated ? :membership_activated : :membership_renewed
        Events.publish_after_commit(event, membership: record, owner: owner, membership_type: record.membership_type)
      end

      def failure(message)
        Result.failure(code: :invalid_argument, errors: [ message ])
      end
    end
  end
end
