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
  has_one :alert_preference, dependent: :destroy

  # Persisted alert toggles, auto-built with defaults on first access so the
  # alert engine and settings page never deal with a nil row.
  def alert_prefs
    alert_preference || create_alert_preference!
  end
end
