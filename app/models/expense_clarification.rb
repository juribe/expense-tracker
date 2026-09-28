# frozen_string_literal: true

# Conversational clarification session tying a WhatsApp user's next replies to
# the incomplete ExpenseCandidates of one inbound message. Persisted so the
# flow survives application restarts and asynchronous job execution.
#
# Lifecycle: pending -> resolved (every candidate complete/converted)
#                    | cancelled (user asked) | abandoned (follow-up limit
#                    reached; remaining candidates stay needs_review)
#
# The partial unique index on user_id WHERE status='pending' guarantees at
# most one open session per user: replies are never ambiguous.
class ExpenseClarification < ApplicationRecord
  STATUSES = %w[pending resolved cancelled abandoned].freeze
  MAX_QUESTIONS = 3

  belongs_to :user
  has_many :expense_clarification_candidates, dependent: :destroy
  has_many :candidates, through: :expense_clarification_candidates,
                        source: :expense_candidate

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :phone_number, presence: true
  validates :questions_count, numericality: { greater_than_or_equal_to: 0 }

  scope :pending, -> { where(status: "pending") }

  def pending?
    status == "pending"
  end

  def resolved?
    status == "resolved"
  end

  def cancelled?
    status == "cancelled"
  end

  def abandoned?
    status == "abandoned"
  end

  def follow_ups_exhausted?
    questions_count >= MAX_QUESTIONS
  end

  # Session candidates that still need review: the ones the flow keeps
  # asking about. Confirmed/discarded ones drop out of the pending set.
  def pending_candidates
    candidates.where(status: "needs_review").order(:id)
  end

  def all_candidates_resolved?
    pending_candidates.empty?
  end

  # Atomically move the session out of pending; returns false when another
  # concurrent reply already resolved/cancelled/abandoned it. Callers use the
  # boolean to drop duplicate or racing replies.
  def close!(new_status)
    update_columns = { status: new_status, updated_at: Time.current }
    updated = self.class.where(id: id, status: "pending").update_all(update_columns)
    self.status = new_status if updated == 1
    updated == 1
  end
end
