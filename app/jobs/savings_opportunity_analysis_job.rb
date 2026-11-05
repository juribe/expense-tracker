# frozen_string_literal: true

# SavingsOpportunityAnalysisJob
# Generates the AI narrative for a user's savings analysis outside the
# request cycle. The deterministic analysis is always available, so the page
# never depends on this job completing; it only upgrades the copy.
class SavingsOpportunityAnalysisJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 1.minute, attempts: 2

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    analysis = SavingsOpportunities::Analysis.new(user: user).call
    SavingsOpportunities::Narrative.new(user: user, analysis: analysis).generate!
    SavingsOpportunities::AnalysisState.write(user.id, "ready")
  rescue StandardError => e
    SavingsOpportunities::AnalysisState.write(user_id, "failed") if user_id.present?
    Rails.logger.error("[SavingsOpportunityAnalysisJob] user=#{user_id} #{e.class}: #{e.message}")
    raise
  end
end
