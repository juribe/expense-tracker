# frozen_string_literal: true

class Category < ApplicationRecord
  belongs_to :parent, class_name: 'Category', optional: true
  has_many :children, class_name: 'Category', foreign_key: :parent_id, dependent: :nullify

  has_many :expenses, dependent: :destroy
  has_many :incomes, dependent: :destroy
  has_many :recurring_transactions, dependent: :destroy

  before_validation :generate_slug, if: -> { slug.blank? || name_changed? }

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validate :parent_must_not_be_self

  scope :active, -> { where(active: true) }
  scope :roots, -> { where(parent_id: nil) }

  default_scope { order(:name) }

  private

  def generate_slug
    self.slug = name.to_s.parameterize
  end

  def parent_must_not_be_self
    return if parent_id.blank? || id.blank?

    errors.add(:parent_id, "can't be the category itself") if parent_id == id
  end
end
