# frozen_string_literal: true

# Budget
# A monthly spending limit for one expense category.
#
# Associations: belongs_to :user, belongs_to :category.
# At most one active budget per (user, category).
class Budget < ApplicationRecord
  belongs_to :user
  belongs_to :category

  validates :monthly_amount, presence: true, numericality: { greater_than: 0 }
  validates :period, presence: true
  validates :active, inclusion: { in: [ true, false ] }
end