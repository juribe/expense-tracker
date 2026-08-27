# frozen_string_literal: true

class Category < ApplicationRecord
  belongs_to :parent, class_name: "Category", optional: true
  belongs_to :user, optional: true
  has_many :children, class_name: "Category", foreign_key: :parent_id, dependent: :nullify

  has_many :expenses, dependent: :destroy
  has_many :incomes, dependent: :destroy
  has_many :transactions, dependent: :destroy
  has_many :recurring_templates, dependent: :destroy

  before_validation :generate_slug, if: -> { slug.blank? || name_changed? }

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :category_type, inclusion: { in: %w[income expense], allow_nil: true }
  validate :parent_must_not_be_self
  validate :default_category_not_owned_by_user
  validate :custom_category_not_named_like_default, on: :create
  validate :unique_custom_category_per_user_and_type

  scope :active, -> { where(active: true) }
  scope :roots, -> { where(parent_id: nil) }
  scope :defaults, -> { where(is_default: true) }
  scope :custom_for_user, ->(user) { where(user_id: user.id, is_default: false) }
  scope :for_user, ->(user) { defaults.or(where(user_id: user.id)) }
  scope :for_user_and_type, ->(user, type) { for_user(user).where(category_type: type) }

  default_scope { order(:name) }

  def default?
    is_default?
  end

  def custom?
    !is_default?
  end

  def editable_by?(user)
    custom? && user_id == user.id
  end

  def deletable_by?(user)
    editable_by?(user)
  end

  private

  def generate_slug
    self.slug = name.to_s.parameterize
  end

  def parent_must_not_be_self
    return if parent_id.blank? || id.blank?

    errors.add(:parent_id, "can't be the category itself") if parent_id == id
  end

  def default_category_not_owned_by_user
    return unless is_default? && user_id.present?

    errors.add(:user_id, "can't be set on default categories")
  end

  def custom_category_not_named_like_default
    return unless name.present? && category_type.present?

    existing_default = Category.defaults
                               .where(category_type: category_type)
                               .where("lower(name) = ?", name.downcase)
                               .exists?
    return unless existing_default

    errors.add(:name, "is already a default category for this type")
  end

  def unique_custom_category_per_user_and_type
    return if user_id.blank? || is_default?
    return unless name.present? && category_type.present?

    existing = Category.where(user_id: user_id, category_type: category_type, is_default: false)
                       .where("lower(name) = ?", name.downcase)
    existing = existing.where.not(id: id) if persisted?
    return unless existing.exists?

    errors.add(:name, "has already been taken for this category type")
  end
end
