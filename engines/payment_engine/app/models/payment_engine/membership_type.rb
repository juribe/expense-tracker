module PaymentEngine
  # Catalog of access levels an application can offer (Free, Premium, Pro...).
  # Types are never hard-deleted while payment options or memberships reference
  # them, and deactivating a type does not revoke existing memberships.
  class MembershipType < ApplicationRecord
    has_many :payment_options, dependent: :restrict_with_error
    has_many :memberships, dependent: :restrict_with_error

    validates :name, presence: true
    validates :slug, presence: true, uniqueness: true,
                     format: { with: /\A[a-z0-9]+(?:[-_][a-z0-9]+)*\z/, message: "must be lowercase alphanumeric with dashes" }

    scope :active, -> { where(active: true) }
    scope :ordered, -> { order(:name) }

    before_destroy :prevent_destroy_with_history

    def to_s
      name
    end

    private

    def prevent_destroy_with_history
      return if payment_options.empty? && memberships.empty?

      errors.add(:base, "cannot delete a membership type with associated history")
      throw :abort
    end
  end
end
