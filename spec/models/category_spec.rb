# spec/models/category_spec.rb
require 'rails_helper'

RSpec.describe Category, type: :model do
  subject { described_class.new }

  describe 'Validations' do
    it 'is valid with valid attributes' do
      category = Category.new(name: 'Food', description: 'Food expenses')
      expect(category).to be_valid
    end

    it 'is invalid without a name' do
      category = Category.new(name: '', description: 'Invalid')
      expect(category.errors[:name]).to include("can't be blank")
    end

    it 'is invalid if name is too short' do
      category = Category.new(name: 'A', description: 'Too short')
      expect(category.errors[:name]).to include('is too short (minimum: 2 characters)')
    end

    it 'is invalid if name is too long' do
      category = Category.new(name: 'A' * 51, description: 'Too long')
      expect(category.errors[:name]).to include('is too long (maximum: 50 characters)')
    end

    it 'is invalid if description is too long' do
      category = Category.new(name: 'Food', description: 'A' * 251)
      expect(category.errors[:description]).to include('is too long (maximum: 250 characters)')
    end

    it 'is invalid if name contains only whitespace' do
      category = Category.new(name: '   ', description: 'Whitespace only')
      expect(category.errors[:name]).to include("can't be blank")
    end
  end

  describe 'Uniqueness' do
    before { Category.create!(name: 'Food', description: 'First entry') }

    it 'is invalid with a duplicate name (case insensitive)' do
      category = Category.new(name: 'food', description: 'Second entry')
      expect(category).not_to be_valid
      expect(category.errors[:name]).to include('has already been taken')
    end

    it 'is invalid with a duplicate name that differs only by leading/trailing spaces' do
      category = Category.new(name: '  Food  ', description: 'Spaces trimmed')
      expect(category).not_to be_valid
      expect(category.errors[:name]).to include('has already been taken')
    end

    it 'is valid when name differs by case after trimming spaces' do
      category = Category.new(name: '  BAR  ', description: 'Different case')
      expect(category).to be_valid
    end
  end
end