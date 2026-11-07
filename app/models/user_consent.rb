# frozen_string_literal: true

# UserConsent
# Audit trail of legal and marketing consents granted by a user.
#
# Associations: belongs_to :user
# Methods: record_registration_acceptances!, record_marketing_consent!,
#          marketing_status, marketing_granted?
#
# Example: UserConsent.record_marketing_consent!(user, granted: false)
class UserConsent < ApplicationRecord
  TERMS = "terms"
  PRIVACY = "privacy"
  MARKETING = "marketing"
  LEGAL_TYPES = [ TERMS, PRIVACY ].freeze
  CONSENT_TYPES = (LEGAL_TYPES + [ MARKETING ]).freeze

  # Mirror the published "last updated" date of each legal document.
  # Bump these when the document changes so acceptances stay auditable.
  # A privacy acceptance is scoped to its recorded version and must not be
  # reused as a general data-processing consent.
  DOCUMENT_VERSIONS = {
    TERMS => "2026-11-06",
    PRIVACY => "2026-11-07"
  }.freeze

  belongs_to :user, inverse_of: :user_consents

  validates :consent_type, inclusion: { in: CONSENT_TYPES }
  validates :occurred_at, presence: true
  validates :granted, inclusion: { in: [ true, false ] }
  validates :document_version, presence: true, if: :legal?
  validates :document_version, absence: true, if: :marketing?

  scope :legal, -> { where(consent_type: LEGAL_TYPES) }
  scope :marketing, -> { where(consent_type: MARKETING) }
  scope :latest_first, -> { order(occurred_at: :desc, created_at: :desc) }

  def self.record_registration_acceptances!(user, marketing_granted: false)
    transaction do
      LEGAL_TYPES.each do |type|
        create!(
          user: user,
          consent_type: type,
          document_version: DOCUMENT_VERSIONS.fetch(type),
          granted: true,
          occurred_at: Time.current
        )
      end

      record_marketing_consent!(user, granted: marketing_granted)
    end
  end

  def self.record_marketing_consent!(user, granted:)
    granted = ActiveModel::Type::Boolean.new.cast(granted) || false

    create!(
      user: user,
      consent_type: MARKETING,
      granted: granted,
      occurred_at: Time.current
    )
  end

  def self.marketing_status(user)
    marketing.where(user: user).latest_first.first
  end

  def self.marketing_granted?(user)
    marketing_status(user)&.granted? || false
  end

  def legal?
    LEGAL_TYPES.include?(consent_type)
  end

  def marketing?
    consent_type == MARKETING
  end
end
