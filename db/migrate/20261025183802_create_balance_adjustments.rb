# frozen_string_literal: true

class CreateBalanceAdjustments < ActiveRecord::Migration[8.1]
  def change
    create_table :balance_adjustments, id: :uuid do |t|
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.references :money_source, null: false, foreign_key: true, type: :uuid
      t.date :effective_date, null: false
      t.decimal :delta, precision: 14, scale: 2, null: false
      t.text :note
      t.timestamps
    end

    add_index :balance_adjustments, [ :user_id, :money_source_id, :effective_date ],
              name: "index_balance_adjustments_on_user_source_date"

    # Backfill the legacy single balance_offset into immutable adjustment
    # records so historical corrections remain auditable and statement-ready.
    reversible do |dir|
      dir.up do
        MoneySource.where.not(balance_offset: 0).find_each do |source|
          BalanceAdjustment.create!(
            user_id: source.user_id,
            money_source_id: source.id,
            effective_date: (source.balance_offset_at || Time.current).to_date,
            delta: source.balance_offset,
            note: source.balance_offset_note
          )
        end
      end
    end
  end
end