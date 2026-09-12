# frozen_string_literal: true

# One dataset row of an evaluation run. The expected_json is the FINAL expense
# result the pipeline should have produced; actual_json and field_results are
# captured after the whole existing Expense Playground processing flow runs.
#
# Associations: belongs_to :evaluation_run
# Methods: finished?, passed?, evaluated_json_valid?, compare expected/actual
class EvaluationCase < ApplicationRecord
  STATUSES = %w[pending passed failed error].freeze

  belongs_to :evaluation_run

  validates :row_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :message, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :row_number, uniqueness: { scope: :evaluation_run_id }

  scope :recent_first, -> { order(row_number: :asc) }
  scope :by_message, ->(term) { where("message ILIKE ?", "%#{term}%") }
  scope :by_status, ->(status) { status.presence ? where(status: status) : all }

  def finished?
    status.in?(%w[passed failed error])
  end

  def passed?
    status == "passed"
  end

  # JSON produced by the pipeline was structurally valid AND the case ran to
  # completion (as opposed to a provider/pipeline error with no result).
  def evaluated_json_valid?
    json_valid?
  end
end