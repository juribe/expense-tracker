# frozen_string_literal: true

class Income < ApplicationRecord
  belongs_to :user
  belongs_to :category

  # Scopes
  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :in_month, ->(date) { where(date: date.beginning_of_month..date.end_of_month) }
  scope :recent, ->(limit = 5) { order(date: :desc).limit(limit) }
end
