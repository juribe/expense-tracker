# frozen_string_literal: true

class FinancialHabitsAnalysisJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 1.minute, attempts: 2

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    analysis = FinancialHabits::Analysis.new(user: user).call
    FinancialHabits::Narrative.new(user: user, analysis: analysis).generate!
    FinancialHabits::AnalysisState.write(user.id, "ready")
  rescue StandardError => e
    FinancialHabits::AnalysisState.write(user_id, "failed") if user_id.present?
    Rails.logger.error("[FinancialHabitsAnalysisJob] user=#{user_id} #{e.class}: #{e.message}")
    raise
  end
end