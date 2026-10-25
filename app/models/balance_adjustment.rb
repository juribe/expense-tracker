# frozen_string_literal: true

# BalanceAdjustment
# Immutable record of a manual balance correction ("Ajustar saldo") made from
# the reconciliation dashboard. It is NOT an income, expense or transfer: it
# only explains part of a money source's balance.
#
# Associations: belongs_to :user, :money_source
# Methods: none (value object persisted for audit and statement rendering)
#
# Example: BalanceAdjustment.create!(user:, money_source:, effective_date:, delta:, note:)
class BalanceAdjustment < ApplicationRecord
  belongs_to :user
  belongs_to :money_source

  validates :effective_date, presence: true
  validates :delta, presence: true, numericality: { other_than: 0 }

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :for_source, ->(source) { where(money_source_id: source.id) }
  scope :chronological, -> { order(:effective_date, :created_at) }
end