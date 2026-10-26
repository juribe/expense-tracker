# frozen_string_literal: true

# A configured email source for a user. Gmail OAuth connections are tracked by
# GmailConnection; this model tracks additional/forwarding sources and their
# independent status.
class EmailSource < ApplicationRecord
  SOURCE_TYPES = %w[gmail forwarding].freeze
  STATUSES = %w[pending_setup pending_verification active error disconnected].freeze

  belongs_to :user

  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :status, inclusion: { in: STATUSES }

  scope :forwarding, -> { where(source_type: "forwarding") }
  scope :gmail, -> { where(source_type: "gmail") }
  scope :active, -> { where(status: "active") }
  scope :pending, -> { where(status: %w[pending_setup pending_verification]) }

  def gmail?
    source_type == "gmail"
  end

  def forwarding?
    source_type == "forwarding"
  end

  def pending_setup?
    status == "pending_setup"
  end

  def pending_verification?
    status == "pending_verification"
  end

  def active?
    status == "active"
  end

  def error?
    status == "error"
  end

  def disconnected?
    status == "disconnected"
  end

  def mark_active!
    update!(status: "active", last_error: nil)
  end

  def mark_error!(message = nil)
    update!(status: "error", last_error: message)
  end

  def disconnect!
    update!(status: "disconnected")
  end
end

# Aliases for alternative naming used by callers/tests.
ForwardedEmailSource = EmailSource
EmailForwardSource = EmailSource
ForwardingSource = EmailSource
InboundEmailSource = EmailSource