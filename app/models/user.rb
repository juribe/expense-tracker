# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :confirmable,
         :passkey_authenticatable, :webauthn_two_factor_authenticatable

  attr_accessor :terms_accepted, :privacy_accepted, :marketing_consent, :registration_form

  NAME_MAX_LENGTH = 255

  validates :name, presence: true, if: :name_required?
  validates :name, length: { maximum: NAME_MAX_LENGTH }
  validates :financial_cycle_start_day,
            numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 28 }
  validates :inbound_email_token, uniqueness: true, allow_nil: true

  before_create :generate_inbound_email_token
  after_create :record_registration_consents, if: :registration_form?, prepend: true

  validates :debt_capacity_target_percentage, :debt_capacity_alert_percentage,
            numericality: { greater_than: 0, less_than_or_equal_to: 100 }
  validate :debt_capacity_thresholds_are_ordered
  validate :registration_consents_accepted, on: :create, if: :registration_form?

  # A start day of 1 means plain calendar months; anything else turns on the
  # pay-cycle grouping everywhere (reports, budgets, dashboard, cuadre).
  def financial_cycles_enabled?
    financial_cycle_start_day.to_i != 1
  end

  has_many :incomes, dependent: :destroy
  has_many :expenses, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :recurring_templates, dependent: :destroy
  has_many :gmail_connections, dependent: :destroy
  has_many :mail_inbound_deliveries, dependent: :destroy
  has_many :processed_emails, dependent: :destroy
  # Records that also reference money sources must be removed before the
  # sources themselves, so their foreign keys and (for payments) balance
  # effects stay consistent.
  has_many :reconciliation_states, dependent: :destroy
  has_many :reconciliation_snapshots, dependent: :destroy
  has_many :balance_adjustments, dependent: :destroy
  has_many :statement_format_mappings, dependent: :destroy
  has_many :spreadsheet_format_mappings, dependent: :destroy
  has_many :ai_requests, dependent: :destroy
  has_many :mcp_idempotency_records, dependent: :delete_all
  has_many :mcp_tool_invocations, dependent: :delete_all
  has_many :categories, dependent: :destroy
  has_many :goals, dependent: :destroy
  has_many :money_sources, dependent: :destroy
  has_many :gmf_monthly_accumulators, dependent: :destroy
  has_many :transfers, dependent: :destroy
  has_many :financial_setups, dependent: :destroy
  has_many :budgets, dependent: :destroy
  has_one :financial_chat, dependent: :destroy
  has_many :spending_alerts, dependent: :destroy
  has_many :transaction_rules, dependent: :destroy
  has_many :expense_playground_runs, dependent: :destroy
  has_many :evaluation_runs, dependent: :destroy
  has_many :activity_classifications, dependent: :destroy
  has_many :expense_candidates, dependent: :destroy
  has_many :expense_clarifications, dependent: :destroy
  has_many :custom_financial_institutions, dependent: :destroy
  has_one :alert_preference, dependent: :destroy
  has_one :onboarding_progress, dependent: :destroy
  has_many :email_sources, dependent: :destroy
  has_many :email_forwarding_verifications, dependent: :destroy
  has_many :mcp_access_tokens, dependent: :destroy
  has_many :recovery_codes, dependent: :destroy
  has_one :totp_credential, dependent: :destroy
  has_many :user_consents, dependent: :destroy, inverse_of: :user

  # WhatsApp linking: connections and pending tokens die with the account;
  # identities only nullify their claim so the historical row survives.
  has_many :whatsapp_connections, dependent: :destroy
  has_many :pending_whatsapp_connections, dependent: :destroy
  has_many :whatsapp_identities, foreign_key: :claimed_by_user_id, dependent: :nullify, inverse_of: :claimed_by_user

  # Two-factor authentication is opt-in. A passkey is a complete primary
  # authentication method and does not enable a second factor by itself.
  # Password logins require a second factor when the user has either a
  # second-factor WebAuthn key or TOTP configured.
  def second_factor_enabled?
    second_factor_webauthn_credentials.exists? || totp_enabled?
  end

  def totp_enabled?
    totp_credential.present?
  end

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

  # Lazily mint a stable token so users created without callbacks (fixtures,
  # direct inserts) still get a usable forwarding address.
  def inbound_email_token
    value = self[:inbound_email_token]
    return value if value.present?

    generate_inbound_email_token
    if persisted? && self[:inbound_email_token].present?
      update_column(:inbound_email_token, self[:inbound_email_token])
    end
    self[:inbound_email_token]
  end

  # Stable, unique forwarding address for this user. The shared mailbox
  # receives everything; the alias identifies the recipient.
  def forwarding_address
    base = ENV["INBOUND_EMAIL_RECIPIENT"].presence || "recibido@expense-tracker.com"
    local, domain = base.split("@", 2)
    return base if local.blank? || domain.blank? || inbound_email_token.blank?

    "#{local}+#{inbound_email_token}@#{domain}"
  end
  alias inbound_email_address forwarding_address
  alias email_alias forwarding_address
  alias inbound_email_alias forwarding_address
  alias personalized_email forwarding_address
  alias forwarding_email forwarding_address
  alias inbound_alias forwarding_address

  def ensure_inbound_email_token!
    generate_inbound_email_token if inbound_email_token.blank?
    save! if changed?
    inbound_email_token
  end

  private

  def name_required?
    registration_form? || (persisted? && will_save_change_to_name?)
  end

  def registration_form?
    ActiveModel::Type::Boolean.new.cast(registration_form)
  end

  def registration_consents_accepted
    errors.add(:base, I18n.t("auth.consents.terms_required")) unless accepted_value?(terms_accepted)
    errors.add(:base, I18n.t("auth.consents.privacy_required")) unless accepted_value?(privacy_accepted)
  end

  def record_registration_consents
    UserConsent.record_registration_acceptances!(
      self,
      marketing_granted: accepted_value?(marketing_consent)
    )
  end

  def accepted_value?(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end

  def generate_inbound_email_token
    return if self[:inbound_email_token].present?

    loop do
      token = SecureRandom.alphanumeric(8).downcase
      break self.inbound_email_token = token unless self.class.exists?(inbound_email_token: token)
    end
  end

  def debt_capacity_thresholds_are_ordered
    return if debt_capacity_target_percentage.blank? || debt_capacity_alert_percentage.blank?
    return if debt_capacity_alert_percentage >= debt_capacity_target_percentage

    errors.add(:debt_capacity_alert_percentage, :greater_than_or_equal_to_target)
  end
end
