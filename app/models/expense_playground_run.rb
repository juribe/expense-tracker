# frozen_string_literal: true

# One execution of the expense ingestion pipeline, persisted so the
# Playground history survives sessions and future evaluation features can
# compare runs against expected results.
#
# PRIVACY: raw uploaded images are NEVER stored here (nor anywhere in the
# playground). Only the channel metadata, the extracted candidate, and the
# pipeline steps are kept.
class ExpensePlaygroundRun < ApplicationRecord
  STATUSES = %w[ok failed].freeze

  belongs_to :user
  belongs_to :expense, class_name: "Transaction", optional: true

  validates :input_type, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent_first, -> { order(created_at: :desc) }

  # Builds a run from a pipeline result. `input_label` is a short human
  # identifier for the input (text snippet or image filename) — never the
  # full image payload.
  def self.record!(user:, input_type:, input_label: nil, result:)
    create!(
      user: user,
      input_type: input_type.to_s,
      input_label: input_label&.truncate(200),
      engine: result.engine,
      duration_ms: result.duration_ms,
      status: result.ok? ? "ok" : "failed",
      candidate: result.candidate&.as_json || {},
      steps: result.steps,
      error_messages: result.errors,
      warnings: result.warnings
    )
  end

  def ok?
    status == "ok"
  end

  # History projection for the UI table.
  def to_history_entry
    {
      id: id,
      ts: created_at.to_i * 1000,
      type: input_type,
      label: input_label,
      candidate: candidate,
      steps: steps,
      ok: ok?,
      confidence: candidate["confidence"],
      errors: error_messages,
      expense_id: expense_id
    }
  end
end
