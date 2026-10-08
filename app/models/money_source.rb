# frozen_string_literal: true

# MoneySource
# Common financial-source entity (account, debit_card, credit_card, cash,
# wallet, pocket, loan). Credit/debt-specific details live on a CreditAccount.
# A pocket is generic assigned-money within the user's assets ("Bolsillo"):
# it is never a payment source (money must be moved out to a real account
# first) and it cannot pay a debt directly.
#
# Associations: belongs_to :user/parent, has_many children/transactions/
#   recurring_templates/outgoing_transfers/incoming_transfers, has_one :credit_account,
#   has_one :recognition (Source Recognition identifiers)
# Methods: balance, used_credit, available_credit, debt?, credit_card?, loan?,
#   payment_source?, funding_source?, debt_payment_target?
#
# Example: source.used_credit
class MoneySource < ApplicationRecord
  KINDS = %w[account debit_card credit_card cash wallet pocket loan].freeze

  include Reconciliation::Invalidatable
  # Flavor within a kind, set by the wizard's loan step / statement import.
  # For loans it drives the capabilities below (revolving disburses money,
  # the rest are debts only); other kinds leave it nil.
  SUB_KINDS = %w[revolving personal vehicle mortgage education business].freeze
  # Kinds that can directly pay an expense. Credit cards pay AND receive
  # debt payments (two independent roles). Pockets are deliberately excluded:
  # their money is assigned, so it must be moved back to a real account
  # before it can be spent.
  PAYMENT_KINDS = %w[cash account debit_card wallet credit_card].freeze

  belongs_to :user
  belongs_to :parent, class_name: "MoneySource", optional: true
  has_many :children, class_name: "MoneySource", foreign_key: :parent_id, dependent: :nullify
  has_many :transactions, dependent: :nullify
  has_many :recurring_templates, dependent: :nullify
  has_many :outgoing_transfers, class_name: "Transfer", foreign_key: :from_source_id, dependent: :destroy
  has_many :incoming_transfers, class_name: "Transfer", foreign_key: :to_source_id, dependent: :destroy
  # Deleting a pocket that still backs goals is blocked: the user removes the
  # goals first so nothing disappears silently.
  has_many :goals, class_name: "Goal", foreign_key: :pocket_id, dependent: :restrict_with_error
  has_many :goal_allocations, class_name: "GoalAllocation", foreign_key: :pocket_id, dependent: :delete_all
  has_one :credit_account, dependent: :destroy
  has_many :payments, foreign_key: :money_source_id, dependent: :restrict_with_error
  has_one :credit_projection, dependent: :destroy
  has_many :credit_scenarios, dependent: :destroy
  has_one :recognition, class_name: "MoneySourceRecognition", dependent: :destroy
  has_many :recognition_identifiers, through: :recognition, source: :recognition_identifiers

  accepts_nested_attributes_for :credit_account, allow_destroy: true

  validates :name, presence: true
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :sub_kind, inclusion: { in: SUB_KINDS }, allow_blank: true
  validates :starting_balance, numericality: true

  scope :active, -> { where(active: true) }
  scope :by_kind, ->(kind) { where(kind: kind) }
  scope :pockets, -> { by_kind("pocket") }

  # Operation-specific source pools. Call sites chain .active so disabled
  # sources never reach the LLM, the WhatsApp lists or the resolver.
  scope :payment_sources, -> { where(kind: PAYMENT_KINDS) }
  scope :funding_sources, -> { by_kind("loan").where(sub_kind: "revolving") }
  scope :debt_payment_targets, -> { where(kind: %w[credit_card loan]) }

  # Sources that can originate a payment, with credit data loaded for
  # display_name. Loans never pay an expense directly — their money lives in
  # the account they were disbursed to (see #payment_source?).
  def self.payment_origins(user)
    user.money_sources.active.payment_sources.includes(:credit_account).order(:kind, :name)
  end

  before_validation :normalize_kind
  before_validation :normalize_sub_kind
  before_validation :normalize_identifier_to_last_four

  # A new source starts with its starting balance; subsequent movements move
  # it via BalanceSync deltas.
  before_create :init_cached_balance_from_starting_balance

  # Changing the starting balance shifts the cached balance by the same delta
  # in before_update so it stays aligned (after_commit would double-apply on
  # reload patterns and flush out of the same transaction as the attribute).
  before_update :sync_cached_balance_with_starting_balance, if: :starting_balance_changed?

  # Cached saldo — maintained incrementally by MoneySources::BalanceSync on
  # every transaction/transfer write. O(1) per write instead of re-aggregating
  # potentially tens of thousands of rows on every render.
  #
  # balance_offset is the persistent "Ajustar saldo" correction from the
  # reconciliation dashboard (no transaction behind it), so it is part of the
  # visible balance and survives BalanceSync.rebuild! recomputes.
  def balance
    cached_balance.to_d + balance_offset.to_d
  end

  def transactions_amount_sum
    transactions.sum(:amount).to_d
  end

  def credit_card?
    kind == "credit_card"
  end

  def loan?
    kind == "loan"
  end

  def debit_card?
    kind == "debit_card"
  end

  def pocket?
    kind == "pocket"
  end

  # Money currently reserved for goals inside this pocket. Only meaningful
  # for pockets; the money never leaves the pocket, it is just earmarked.
  def allocated_amount
    return 0.to_d unless pocket?

    goal_allocations.sum(:amount).to_d
  end

  def unallocated_amount
    return balance unless pocket?

    [ balance - allocated_amount, 0 ].max
  end

  # Can this source pay an expense directly? Loans never pay — their money
  # lives in the account where it was disbursed, so expenses belong there.
  def payment_source?
    PAYMENT_KINDS.include?(kind)
  end

  # Can money be disbursed/obtained from this source? Only revolving loans:
  # a free-investment loan deposits into a savings account once, so the
  # account — not the loan — is the reusable funding source.
  def funding_source?
    loan? && sub_kind == "revolving"
  end

  # Can this source receive debt payments? Credit cards (pay off the card
  # balance) and every loan, regardless of subtype.
  def debt_payment_target?
    debt?
  end

  def debt?
    credit_card? || loan?
  end

  def credit_account?
    credit_account.present?
  end

  # Positive magnitude of what is owed. balance returns the negative for debt
  # sources so existing debt-means-negative rendering stays consistent.
  def used_credit
    return 0 unless debt?

    [ -balance, 0 ].max
  end

  def outstanding_balance
    return nil unless loan?

    credit_account&.outstanding_balance || credit_account&.principal_amount
  end

  def credit_limit
    credit_account&.credit_limit
  end

  def available_credit
    return nil if credit_limit.to_i <= 0

    [ credit_limit - used_credit, 0 ].max
  end

  def credit_utilization
    return 0 if credit_limit.to_i <= 0

    (used_credit / credit_limit.to_d * 100).round(1)
  end

  delegate :principal_amount, :installment_amount, :installment_count,
           :payment_frequency, :statement_day, :payment_due_day,
           :interest_rate, :interest_rate_type, :card_brand, :card_last_four,
           :start_date, :end_date, :interest_rate_label,
           to: :credit_account, allow_nil: true

  def remaining_installments
    return nil if installment_count.nil? || principal_amount.to_i <= 0 || outstanding_balance.nil?

    (installment_count * (outstanding_balance / principal_amount.to_d)).round
  end

  def repayment_progress
    return 0 if principal_amount.to_i <= 0 || outstanding_balance.nil?

    (outstanding_balance / principal_amount.to_d * 100).round(1)
  end

  def balance_label
    if debit_card? && parent
      "→ #{parent.name}"
    else
      ActionController::Base.helpers.number_to_currency(balance)
    end
  end

  def display_name
    parts = [ name ]
    parts << bank if bank.present?
    # Touch credit_account unconditionally so Bullet sees the association
    # accessed even when the list has no credit cards (nil id loads nothing).
    digits = credit_account&.card_last_four
    parts << digits if credit_card? && digits.present?
    parts.join(" · ")
  end

  # Whether minimum recognition configuration exists: at least one CONFIRMED
  # identifier of any kind. Persisted suggestions alone do not count — the
  # user must review and accept them first.
  def recognition_configured?
    recognition_identifiers.confirmed.any?
  end

  # The source's last four digits, used as a recognition signal. Re-derived
  # from the raw stored value so only the ENDING digits are ever used (never a
  # random or partial slice). Falls back to the credit card's last four and
  # returns nil when there aren't exactly four digits to work with.
  def last_four
    raw = identifier.presence
    raw ||= credit_account.card_last_four if credit_card? && credit_account
    ending = raw.to_s.gsub(/\D/, "").chars.last(4).join
    ending if ending.length == 4
  end

  # Lazily builds the recognition record (persisted on save) without creating
  # it just for a look-up.
  def ensure_recognition
    recognition || build_recognition
  end

  def institution
    bank.to_s.strip.downcase.presence
  end

  private

  def init_cached_balance_from_starting_balance
    self.cached_balance = starting_balance.to_d
  end

  def sync_cached_balance_with_starting_balance
    self.cached_balance = cached_balance.to_d + (starting_balance - starting_balance_was)
  end

  def normalize_kind
    self.kind = kind.to_s.downcase if kind.present?
  end

  def normalize_sub_kind
    self.sub_kind = sub_kind.to_s.downcase.presence
  end

  # SECURITY: never store a full account / card / loan number. Only the last
  # four digits are saved, regardless of what the form, import, or API provides.
  def normalize_identifier_to_last_four
    # Store NULL (not "") when no identifier was given, so the unique index on
    # (user_id, identifier) allows several sources without one.
    self.identifier = nil if identifier.blank?
    if kind == "cash" || kind == "wallet" || kind == "pocket"
      # Pockets never carry an account number: their money is detached from
      # any real deposit account.
      self.identifier = nil
      return
    end

    digits = identifier.to_s.gsub(/\D/, "")
    self.identifier = digits.chars.last(4).join if digits.present?
  end
end
