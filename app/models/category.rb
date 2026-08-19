class Category < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :description, presence: true

  default_scope { order(:name) }
end