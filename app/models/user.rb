# frozen_string_literal: true

class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :incomes, dependent: :destroy
  has_many :expenses, dependent: :destroy
  has_many :recurring_transactions, dependent: :destroy
  has_many :monthly_expenses, dependent: :destroy
end
