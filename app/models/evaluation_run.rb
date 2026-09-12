# frozen_string_literal: true

# A recorded AI evaluation: a dataset processed end-to-end through the
# existing Expense Playground pipeline with a single provider/model override.
#
# Associations: belongs_to :user, has_many :evaluation_cases (dependent: :destroy)
# Methods: progress, finished?, complete!, metric
#
# Evaluation records are kept separate from production financial records; they
# only reference the message text and pipeline output captured per case.
class EvaluationRun < ApplicationRecord
  STATUSES = %w[pending running completed failed].freeze

  belongs_to :user
  has_many :evaluation_cases, dependent: :destroy

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :total_cases, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :recent_first, -> { order(created_at: :desc) }

  def pending?
    status == "pending"
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  # Fractional completion based on cases that reached a terminal status.
  def progress
    return 0.0 if total_cases.zero?

    (finished_cases.count.to_f / total_cases).clamp(0.0, 1.0)
  end

  def finished_cases
    evaluation_cases.where(status: %w[passed failed error])
  end

  # Marks the run completed once every case reached a terminal status and
  # freezes the aggregated metrics.
  def update_progress!
    if finished_cases.count >= total_cases
      update!(status: "completed", completed_at: Time.current, metrics: ExpensePlayground::Evaluations::Metrics.for(self))
    elsif status != "running"
      update!(status: "running", started_at: Time.current)
    else
      touch(:updated_at)
    end
  end

  # Fails the whole run immediately (e.g. dataset validation problems before
  # any case was queued).
  def fail!(reason: nil)
    update!(status: "failed", completed_at: Time.current, metrics: ExpensePlayground::Evaluations::Metrics.for(self, error: reason))
  end

  # Reads a nested metric from the persisted metrics jsonb column.
  def metric(key)
    ExpensePlayground::Evaluations::Metrics.metric(metrics, key)
  end

  def to_evaluation_entry
    {
      id: id,
      dataset_name: dataset_name,
      dataset_version: dataset_version,
      provider: provider,
      model: model,
      prompt_version: prompt_version,
      status: status,
      total_cases: total_cases,
      progress: progress,
      created_at: created_at.iso8601,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601,
      metrics: metrics
    }
  end
end