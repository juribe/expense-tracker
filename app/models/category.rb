class Category < ApplicationRecord
  validates :name, presence: true, uniqueness: true
  validates :description, presence: true

  has_many :expenses, dependent: :destroy

  default_scope { order(:name) }
end