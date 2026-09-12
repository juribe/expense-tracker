# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :incomes, dependent: :destroy
  has_many :expenses, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :recurring_templates, dependent: :destroy
  has_many :gmail_connections, dependent: :destroy
  has_many :processed_emails, dependent: :destroy
  has_many :money_sources, dependent: :destroy
  has_many :transfers, dependent: :destroy
  has_many :financial_setups, dependent: :destroy
  has_many :budgets, dependent: :destroy
  has_many :spending_alerts, dependent: :destroy
  has_many :transaction_rules, dependent: :destroy
  has_many :expense_playground_runs, dependent: :destroy
  has_many :evaluation_runs, dependent: :destroy
  has_many :activity_classifications, dependent: :destroy
  has_one :alert_preference, dependent: :destroy

  # Persisted alert toggles, auto-built with defaults on first access so the
  # alert engine and settings page never deal with a nil row.
  def alert_prefs
    alert_preference || create_alert_preference!
  end

  # Transaction-rule suggestions the user dismissed, indexed by normalized
  # merchant text so the suggestion panels hide them without re-asking.
  def dismiss_rule_suggestion!(merchant)
    normalized = merchant.to_s.strip.downcase
    return if normalized.blank?
    return if rule_suggestion_dismissed?(normalized)

    update!(dismissed_rule_suggestions: dismissed_rule_suggestions + [ normalized ])
  end

  def rule_suggestion_dismissed?(merchant)
    dismissed_rule_suggestions.include?(merchant.to_s.strip.downcase)
  end
end
