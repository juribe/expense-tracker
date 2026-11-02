module PaymentEngine
  # Access right owned by any host model through a polymorphic association.
  # Access is always derived from status AND dates: a membership whose
  # expires_at has passed never grants access, even if the expiration job has
  # not run yet. Rows are kept as history after expiring or being canceled.
  class Membership < ApplicationRecord
    STATUSES = %w[pending trialing active expired canceled].freeze
    ACCESS_STATUSES = %w[trialing active].freeze
    OPEN_STATUSES = ACCESS_STATUSES

    belongs_to :owner, polymorphic: true
    belongs_to :membership_type
    belongs_to :payment_option, optional: true

    has_many :purchases, dependent: :restrict_with_error
    has_many :payments, dependent: :restrict_with_error
    has_many :subscriptions, dependent: :restrict_with_error

    validates :status, inclusion: { in: STATUSES }
    validates :starts_at, presence: true
    validate :expires_after_starts

    before_destroy :prevent_destroy

    scope :currently_active, -> {
      where(status: ACCESS_STATUSES)
        .where("starts_at <= ?", Time.current)
        .where("expires_at IS NULL OR expires_at > ?", Time.current)
    }
    scope :expired_by_date, -> {
      where(status: ACCESS_STATUSES)
        .where("expires_at IS NOT NULL AND expires_at <= ?", Time.current)
    }
    scope :for_owner, ->(owner) {
      where(owner_type: owner.class.polymorphic_name, owner_id: owner.id)
    }
    scope :for_type_slug, ->(slug) {
      joins(:membership_type).merge(MembershipType.where(slug: slug.to_s))
    }

    class << self
      def active?(owner, type: nil)
        query_for(owner, type: type).currently_active.exists?
      end

      # Deterministic priority when several memberships are active:
      # 1) active before trialing, 2) no expiration (indefinite) first,
      # 3) latest expiration, 4) latest start, 5) highest id.
      def current(owner, type: nil)
        query_for(owner, type: type).currently_active
          .order(
            Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'trialing' THEN 1 ELSE 2 END"),
            Arel.sql("(expires_at IS NULL) DESC"),
            expires_at: :desc,
            starts_at: :desc,
            id: :desc
          )
          .first
      end

      def current_type(owner, type: nil)
        current(owner, type: type)&.membership_type
      end

      def all_active(owner, type: nil)
        query_for(owner, type: type).currently_active
      end

      def expires_at(owner, type: nil)
        current(owner, type: type)&.expires_at
      end

      def days_remaining(owner, type: nil)
        current(owner, type: type)&.days_remaining
      end

      def expiring_soon?(owner, days: 7, type: nil)
        membership = current(owner, type: type)
        membership.present? && membership.expiring_soon?(days: days)
      end

      def has_type?(owner, slug:, active_only: true)
        scope = for_owner(owner).for_type_slug(slug)
        scope = scope.currently_active if active_only
        scope.exists?
      end

      private

      def query_for(owner, type: nil)
        scope = for_owner(owner)
        type.present? ? scope.for_type_slug(type) : scope
      end
    end

    def active?
      ACCESS_STATUSES.include?(status) && starts_at.present? && starts_at <= now && !expired_by_date?
    end

    def pending?
      status == "pending"
    end

    def trialing?
      status == "trialing"
    end

    def expired?
      status == "expired" || expired_by_date?
    end

    def canceled?
      status == "canceled"
    end

    def expiring_soon?(days: 7)
      active? && expires_at.present? && expires_at <= now + days.to_i.days
    end

    def days_remaining
      return nil if expires_at.nil?
      return 0 unless expires_at > now

      ((expires_at - now) / 1.day).floor
    end

    # Seconds until expiration, or nil for an indefinite membership.
    def expires_in
      return nil if expires_at.nil?

      [ (expires_at - now).to_i, 0 ].max
    end

    def remaining_time
      seconds = expires_in
      seconds.nil? ? nil : ActiveSupport::Duration.build(seconds)
    end

    def subscription
      subscriptions.order(
        Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'trialing' THEN 1 WHEN 'past_due' THEN 2 ELSE 3 END"),
        id: :desc
      ).first
    end

    def duration
      payment_option&.duration || Duration.new(interval: "day", count: 1)
    end

    private

    def now
      Time.current
    end

    def expired_by_date?
      expires_at.present? && expires_at <= now
    end

    def expires_after_starts
      return if starts_at.blank? || expires_at.blank?
      return if expires_at > starts_at

      errors.add(:expires_at, "must be after starts_at")
    end

    def prevent_destroy
      errors.add(:base, "memberships are kept as history")
      throw :abort
    end
  end
end
