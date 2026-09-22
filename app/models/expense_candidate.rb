# frozen_string_literal: true

# Persisted expense candidate from AI parsing or any ingestion source.
# Candidates are created with incomplete or uncertain data and reviewed
# by the user before becoming final Expenses.
#
# Lifecycle: needs_review -> ready -> confirmed (or discarded at any point)
#
# Associations: belongs_to :user, belongs_to :category (optional),
#   belongs_to :money_source (optional), belongs_to :expense (set on confirm)
#
# Example:
#   candidate = ExpenseCandidate.create!(user: user, amount: 50000, date: Date.current, source: "text")
#   candidate.confirm!  # creates Expense, sets expense_id
class ExpenseCandidate < ApplicationRecord
  STATUSES = %w[needs_review ready confirmed discarded].freeze
  REVIEWABLE_FIELDS = %i[category_id money_source_id].freeze
  REQUIRED_FIELDS = %i[amount date].freeze
  DEFAULT_CURRENCY = "COP"

  # Transient attributes used by CandidateDetector and pipeline but not persisted.
  attr_accessor :currency, :merchant, :category_name, :money_source_name,
                :classification_source, :suggested_category_id,
                :suggested_category_name, :duplicate, :warnings,
                :money_source_source

  belongs_to :user
  belongs_to :category, optional: true
  belongs_to :money_source, optional: true
  belongs_to :expense, optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :source, presence: true
  validates :amount, numericality: { greater_than: 0 }, allow_nil: true

  scope :for_user, ->(user) { where(user: user) }
  scope :pending, -> { where(status: %w[needs_review ready]) }
  scope :needs_review, -> { where(status: "needs_review") }
  scope :ready, -> { where(status: "ready") }
  scope :confirmed, -> { where(status: "confirmed") }
  scope :discarded, -> { where(status: "discarded") }

  def as_json(options = {})
    super(options).merge(
      "currency" => currency,
      "merchant" => merchant,
      "category_name" => category_name,
      "money_source_name" => money_source_name,
      "classification_source" => classification_source,
      "suggested_category_name" => suggested_category_name,
      "suggested_category_id" => suggested_category_id,
      "duplicate" => duplicate,
      "warnings" => warnings
    )
  end

  # Build an unpersisted candidate from hash params (e.g. the playground API).
  # User can be passed as a parameter or extracted from the hash.
  def self.from_h(hash, user: nil)
    hash = (hash.respond_to?(:to_unsafe_h) ? hash.to_unsafe_h : hash).symbolize_keys
    new(
      user: user || hash[:user],
      amount: parse_amount(hash[:amount]),
      currency: hash[:currency],
      category_id: hash[:category_id].presence&.to_i,
      category_name: hash[:category_name].presence,
      description: hash[:description].presence,
      merchant: hash[:merchant].presence,
      date: parse_date(hash[:date]),
      source: hash[:source].presence || "playground",
      confidence: hash[:confidence],
      money_source_id: hash[:money_source_id].presence&.to_i,
      money_source_name: hash[:money_source_name].presence,
      classification_source: hash[:classification_source].presence,
      money_source_source: hash[:money_source_source].presence,
      suggested_category_id: hash[:suggested_category_id].presence&.to_i,
      suggested_category_name: hash[:suggested_category_name].presence,
      duplicate: hash[:duplicate],
      warnings: Array(hash[:warnings])
    )
  end

  before_validation :set_defaults, on: :create
  after_validation :set_initial_status, on: :create
  after_save :sync_missing_fields, if: :saved_change_to_category_id?

  def needs_review?
    status == "needs_review"
  end

  def ready?
    status == "ready"
  end

  def confirmed?
    status == "confirmed"
  end

  def discarded?
    status == "discarded"
  end

  # Compute which required fields are currently missing or nil.
  # Individual checks rendered by the pipeline/debug view.
  def checks
    [
      { label: "Amount present", passed: amount.is_a?(Numeric) && amount.positive? },
      { label: "Currency detected", passed: currency.present? },
      { label: "Category assigned", passed: category_id.present? || category_name.present? },
      { label: "Valid date", passed: date.present? }
    ]
  end

  # Lightweight validity check for pipeline processing. Does not require
  # a user (candidates are persisted later with user assignment).
  def valid_for_pipeline?
    checks.all? { |check| check[:passed] }
  end

  def missing_fields
    fields = []
    fields << "amount" if amount.nil?
    fields << "date" if date.nil?
    fields << "category_id" if category_id.nil?
    fields << "money_source_id" if money_source_id.nil?
    fields
  end

  # Recompute missing_fields from current attribute values and persist.
  def recalculate_missing_fields!
    update_column(:missing_fields, missing_fields)
  end

  # Update status based on current missing_fields, but only if the
  # candidate is still in a reviewable state.
  def recalculate_status!
    return unless %w[needs_review ready].include?(status)

    new_status = missing_fields.empty? ? "ready" : "needs_review"
    update!(status: new_status) if status != new_status
  end

  # Create the final Expense from this candidate and mark as confirmed.
  # Raises ActiveRecord::RecordInvalid if required fields are missing.
  def confirm!
    return if confirmed? && expense_id.present?

    ActiveRecord::Base.transaction do
      expense = create_expense_from_candidate!
      update!(
        status: "confirmed",
        expense_id: expense.id,
        confirmed_at: Time.current
      )
    end
  end

  # Mark as discarded.
  def discard!
    update!(status: "discarded", discarded_at: Time.current)
  end

  private

  def set_defaults
    self.status ||= "needs_review"
    self.source ||= "text"
    self.missing_fields ||= []
    self.metadata ||= {}
  end

  def set_initial_status
    return unless status == "needs_review"

    self.status = missing_fields.empty? ? "ready" : "needs_review"
  end

  def self.parse_amount(value)
    return value if value.is_a?(Numeric)
    return nil if value.blank?

    BigDecimal(value.to_s.gsub(/[^0-9.\-]/, ""))
  rescue ArgumentError, TypeError
    nil
  end

  def self.parse_date(value)
    return value if value.is_a?(Date)
    return nil if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError, Date::Error, TypeError
    begin
      Date.parse(value.to_s)
    rescue ArgumentError, Date::Error, TypeError
      nil
    end
  end

  def sync_missing_fields
    recalculate_missing_fields!
  end

  def create_expense_from_candidate!
    raise ActiveRecord::RecordInvalid, self if missing_fields.intersect?(%w[amount date])

    Expense.create!(
      user: user,
      category: category,
      amount: amount,
      description: description.presence&.truncate(255),
      date: date,
      source: "ai",
      money_source: money_source
    )
  end
end
