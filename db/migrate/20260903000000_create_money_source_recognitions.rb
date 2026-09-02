# frozen_string_literal: true

# Creates the Source Recognition tables: MoneySourceRecognition holds the
# config for one Money Source, with typed recognition identifiers
# (keyword / sender / domain / subject / header).
class CreateMoneySourceRecognitions < ActiveRecord::Migration[8.0]
  def change
    create_table :money_source_recognitions do |t|
      t.references :money_source, null: false, foreign_key: true, index: { unique: true }
      t.timestamps
    end

    create_table :money_source_recognition_identifiers do |t|
      t.references :money_source_recognition, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :value, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [ :money_source_recognition_id, :kind, :value ],
              unique: true,
              name: "index_mrs_identifiers_on_recognition_kind_value"
      t.index [ :money_source_recognition_id, :kind, :position ],
              name: "index_mrs_identifiers_on_recognition_kind_position"
    end
  end
end
