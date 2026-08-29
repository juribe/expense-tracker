# frozen_string_literal: true

class Transfer < ApplicationRecord
  belongs_to :user
  belongs_to :from_source, class_name: "MoneySource"
  belongs_to :to_source, class_name: "MoneySource"

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true
  validate :different_sources

  scope :for_user, ->(user) { where(user_id: user.id) }
  scope :recent, ->(limit = 20) { order(date: :desc, created_at: :desc).limit(limit) }

  private

  def different_sources
    return if from_source_id.blank? || to_source_id.blank?

    errors.add(:to_source, I18n.t("validation.transfer_sources")) if from_source_id == to_source_id
  end
end
