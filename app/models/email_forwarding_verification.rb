# frozen_string_literal: true

# Temporary storage for Gmail forwarding verification messages received through
# the inbound email pipeline. These are never turned into expenses.
class EmailForwardingVerification < ApplicationRecord
  belongs_to :user
  belongs_to :email_source, optional: true, class_name: "EmailSource"

  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ?", Time.current).where(consumed_at: nil) }
  scope :expired, -> { where("expires_at <= ?", Time.current) }
  scope :unexpired, -> { where("expires_at > ?", Time.current) }
  scope :unused, -> { where(consumed_at: nil) }
  scope :pending, -> { active }

  def self.origin_email_from_subject(subject)
    subject.to_s[/recibir correo de\s+([A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,})/i, 1] ||
      subject.to_s[/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i]
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end

  def detected_sender
    self.class.origin_email_from_subject(subject) ||
      sender_email.to_s[/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i]
  end

  def safe_confirmation_url
    MailInbound::ConfirmationUrlValidator.call(confirmation_url)
  end

  def consume!
    update!(consumed_at: Time.current) unless consumed?
  end
end

# Aliases for alternative naming used by callers/tests.
ForwardingVerification = EmailForwardingVerification
InboundEmailVerification = EmailForwardingVerification
EmailVerification = EmailForwardingVerification
