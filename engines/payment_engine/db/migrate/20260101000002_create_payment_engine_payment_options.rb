class CreatePaymentEnginePaymentOptions < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_engine_payment_options do |t|
      t.references :membership_type, null: false,
                   foreign_key: { to_table: :payment_engine_membership_types },
                   index: { name: "index_payment_engine_payment_options_on_membership_type_id" }
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.bigint :price, null: false, default: 0
      t.string :currency, null: false, limit: 3
      t.string :billing_type, null: false, default: "one_time"
      t.string :interval
      t.integer :interval_count, null: false, default: 1
      t.integer :trial_days, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.integer :sort_order, null: false, default: 0
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :payment_engine_payment_options, :slug, unique: true
    add_index :payment_engine_payment_options, [ :membership_type_id, :active ]
    add_check_constraint :payment_engine_payment_options, "price >= 0", name: "payment_options_price_non_negative"
    add_check_constraint :payment_engine_payment_options, "interval_count > 0", name: "payment_options_interval_count_positive"
    add_check_constraint :payment_engine_payment_options, "trial_days >= 0", name: "payment_options_trial_days_non_negative"
    add_check_constraint :payment_engine_payment_options,
                         "billing_type IN ('one_time', 'recurring')",
                         name: "payment_options_billing_type_valid"
    add_check_constraint :payment_engine_payment_options,
                         "interval IS NULL OR interval IN ('day', 'month', 'year')",
                         name: "payment_options_interval_valid"
  end
end
