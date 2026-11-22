# frozen_string_literal: true

class AddMoneyTrackingModes < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :money_tracking_mode, :string, default: "detailed", null: false
    add_column :users, :money_tracking_mode_selected_at, :datetime
    add_column :users, :default_money_source_id, :uuid

    add_check_constraint :users,
                         "money_tracking_mode IN ('simple', 'detailed')",
                         name: "users_money_tracking_mode_check"

    add_index :users, :default_money_source_id
    add_foreign_key :users, :money_sources, column: :default_money_source_id, on_delete: :nullify

    add_column :money_sources, :general, :boolean, default: false, null: false
    add_index :money_sources, :user_id, unique: true, where: "general = true",
                                        name: "index_money_sources_general_per_user"

    # Existing users keep their current (advanced) experience when they already
    # manage sources; accounts without sources start in the simple flow. Every
    # account receives its General source as part of the same idempotent task.
    say_with_time "Backfilling money tracking modes and General sources" do
      counts = MoneyTracking::Backfill.call
      say counts.inspect
    end
  end

  def down
    execute "UPDATE money_sources SET kind = 'account' WHERE general = TRUE AND kind = 'general'"

    remove_index :money_sources, name: "index_money_sources_general_per_user"
    remove_column :money_sources, :general

    remove_foreign_key :users, column: :default_money_source_id
    remove_index :users, :default_money_source_id
    remove_check_constraint :users, name: "users_money_tracking_mode_check"
    remove_column :users, :default_money_source_id
    remove_column :users, :money_tracking_mode_selected_at
    remove_column :users, :money_tracking_mode
  end
end
