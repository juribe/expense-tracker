# frozen_string_literal: true

# Catalog tables for the cheap first-stage financial email filter:
# Colombian institutions (aliases/domains/keywords), a global financial
# keyword dictionary and generic subject patterns. All seeded idempotently
# from db/seed_data/*.yml.
class CreateFinancialEmailCatalog < ActiveRecord::Migration[8.0]
  def change
    create_table :financial_institutions do |t|
      t.string :canonical_name, null: false
      t.jsonb :aliases, null: false, default: []
      t.jsonb :domains, null: false, default: []
      t.jsonb :keywords, null: false, default: []
      t.boolean :active, null: false, default: true
      t.timestamps
      t.index :canonical_name, unique: true
    end

    create_table :financial_keywords do |t|
      t.string :value, null: false
      t.string :category, null: false
      t.integer :weight, null: false, default: 1
      t.timestamps
      t.index :value, unique: true
      t.index :category
    end

    create_table :financial_subject_patterns do |t|
      t.string :value, null: false
      t.integer :weight, null: false, default: 2
      t.timestamps
      t.index :value, unique: true
    end
  end
end
