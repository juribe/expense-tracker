class CreatePaymentEngineSubscriptions < ActiveRecord::Migration[7.2]
  def change
    create_table :payment_engine_subscriptions do |t|
      t.references :membership, null: false,
                   foreign_key: { to_table: :payment_engine_memberships },
                   index: { name: "index_payment_engine_subscriptions_on_membership_id" }
      t.references :payment_option, null: false,
                   foreign_key: { to_table: :payment_engine_payment_options },
                   index: { name: "index_payment_engine_subscriptions_on_payment_option_id" }
      t.string :provider, null: false
      t.string :provider_subscription_id
      t.string :status, null: false, default: "active"
      t.bigint :price, null: false, default: 0
      t.string :currency, limit: 3, null: false
      t.string :billing_type
      t.jsonb :duration, null: false, default: {}
      t.datetime :current_period_starts_at
      t.datetime :current_period_ends_at
      t.datetime :next_billing_at
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :canceled_at
      t.datetime :trial_ends_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :payment_engine_subscriptions, [ :provider, :provider_subscription_id ],
              unique: true,
              where: "provider_subscription_id IS NOT NULL",
              name: "index_payment_engine_subscriptions_unique_provider_id"
    add_index :payment_engine_subscriptions, [ :status, :next_billing_at ]
    add_check_constraint :payment_engine_subscriptions, "price >= 0", name: "subscriptions_price_non_negative"
    add_check_constraint :payment_engine_subscriptions,
                         "status IN ('trialing', 'active', 'past_due', 'paused', 'canceled', 'expired')",
                         name: "subscriptions_status_valid"
  end
end
