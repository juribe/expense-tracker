# frozen_string_literal: true

# FinancialSetup
# Persisted onboarding wizard state for a user. Stores the current step index,
# the per-step manual/import/skip choice, and draft source rows so the user can
# leave the wizard and resume exactly where they stopped.
#
# Associations: belongs_to :user
# Methods: choice_for, set_choice, draft_sources, replace_draft_sources,
#   completed?, dismissed?, complete!, dismiss!, resume_at
#
# Example: setup.set_choice("credit_cards", "import")
class FinancialSetup < ApplicationRecord
  STATUSES = %w[in_progress completed dismissed].freeze

  belongs_to :user

  validates :status, inclusion: { in: STATUSES }
  validates :current_step, numericality: { only_integer: true, greater_than_or_equal_to: -1 }

  # Per-step manual/import/skip choice. Step keys are normalized to strings so
  # both controller params ("accounts") and wizard symbols (:accounts) work.
  def choice_for(step_key)
    data.dig(step_key.to_s, "choice")
  end

  def set_choice(step_key, choice)
    self.data = data.deep_merge(step_key.to_s => { "choice" => choice.to_s })
  end

  # Draft source rows entered (or extracted) for a step.
  def draft_sources(step_key)
    Array(data.dig(step_key.to_s, "sources"))
  end

  def append_draft_sources(step_key, sources)
    current = draft_sources(step_key)
    
    # Standardize identifier for comparison (remove non-digits)
    normalize_id = ->(id) { id.to_s.gsub(/\D/, "") }
    
    # Combine and deduplicate. Use identifier as primary key.
    # If identifier is missing, fallback to bank + name.
    updated = (current + sources).uniq do |s|
      id = normalize_id.call(s["identifier"])
      # We only treat it as a match if there is actually an ID.
      # If ID is blank, we fall back to bank+name to avoid grouping all "id-less" accounts together.
      id.presence || "#{s["bank"]}-#{s["name"]}"
    end
    
    self.data = data.deep_merge(step_key.to_s => { "sources" => updated })
  end

  def replace_draft_sources(step_key, sources)
    self.data = data.deep_merge(step_key.to_s => { "sources" => sources.any? ? sources : [] })
  end

  # Import review state for a step: extracted sources + transactions + job state.
  def import_state(step_key)
    data.dig(step_key.to_s, "import") || {}
  end

  def set_import_state(step_key, import)
    self.data = data.deep_merge(step_key.to_s => { "import" => import })
  end

  # Completed steps (steps at or before current_step that have a recorded choice).
  def step_count
    data.keys.length
  end

  def completed?
    status == "completed"
  end

  def dismissed?
    status == "dismissed"
  end

  # Whether the user has started the wizard (recorded any data or advanced past
  # the first step). A fresh setup only shows the entry screen.
  def resumable?
    current_step.to_i > 0 || data.present?
  end

  def complete!
    update!(status: "completed", current_step: -1)
  end

  def dismiss!
    update!(status: "dismissed")
  end

  # Clears all wizard progress so the user can start again from the beginning.
  def reset!
    update!(status: "in_progress", current_step: 0, data: {})
  end
end
