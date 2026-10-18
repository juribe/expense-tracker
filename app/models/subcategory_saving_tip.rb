# frozen_string_literal: true

# SubcategorySavingTip
# Database-backed savings advice shown in Category Insight for a subcategory.
#
# Associations: belongs_to :subcategory (Category)
# Methods: none
#
# Example: SubcategorySavingTip.active.ordered
class SubcategorySavingTip < ApplicationRecord
  belongs_to :subcategory, class_name: "Category"

  validates :title, presence: true
  validates :body, presence: true
  validates :active, inclusion: { in: [ true, false ] }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :created_at) }
end
