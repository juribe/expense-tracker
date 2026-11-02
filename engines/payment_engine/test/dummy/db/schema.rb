# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_01_000008) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "payment_engine_membership_types", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "active" ], name: "index_payment_engine_membership_types_on_active"
    t.index [ "slug" ], name: "index_payment_engine_membership_types_on_slug", unique: true
  end

  create_table "payment_engine_memberships", force: :cascade do |t|
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.bigint "membership_type_id", null: false
    t.bigint "payment_option_id"
    t.string "status", default: "pending", null: false
    t.datetime "starts_at", null: false
    t.datetime "expires_at"
    t.datetime "canceled_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "membership_type_id" ], name: "index_payment_engine_memberships_on_membership_type_id"
    t.index [ "owner_type", "owner_id", "membership_type_id", "status" ], name: "index_payment_engine_memberships_owner_type_status"
    t.index [ "owner_type", "owner_id", "membership_type_id" ], name: "index_payment_engine_memberships_unique_open_access", unique: true, where: "((status)::text = ANY (ARRAY[('active'::character varying)::text, ('trialing'::character varying)::text]))"
    t.index [ "owner_type", "owner_id" ], name: "index_payment_engine_memberships_on_owner_type_and_owner_id"
    t.index [ "payment_option_id" ], name: "index_payment_engine_memberships_on_payment_option_id"
    t.index [ "status", "expires_at" ], name: "index_payment_engine_memberships_on_status_and_expires_at"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'trialing'::character varying::text, 'active'::character varying::text, 'expired'::character varying::text, 'canceled'::character varying::text])", name: "memberships_status_valid"
  end

  create_table "payment_engine_payment_options", force: :cascade do |t|
    t.bigint "membership_type_id", null: false
    t.string "name", null: false
    t.string "slug", null: false
    t.text "description"
    t.bigint "price", default: 0, null: false
    t.string "currency", limit: 3, null: false
    t.string "billing_type", default: "one_time", null: false
    t.string "interval"
    t.integer "interval_count", default: 1, null: false
    t.integer "trial_days", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.integer "sort_order", default: 0, null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "membership_type_id", "active" ], name: "idx_on_membership_type_id_active_af51d992aa"
    t.index [ "membership_type_id" ], name: "index_payment_engine_payment_options_on_membership_type_id"
    t.index [ "slug" ], name: "index_payment_engine_payment_options_on_slug", unique: true
    t.check_constraint "\"interval\" IS NULL OR (\"interval\"::text = ANY (ARRAY['day'::character varying::text, 'month'::character varying::text, 'year'::character varying::text]))", name: "payment_options_interval_valid"
    t.check_constraint "billing_type::text = ANY (ARRAY['one_time'::character varying::text, 'recurring'::character varying::text])", name: "payment_options_billing_type_valid"
    t.check_constraint "interval_count > 0", name: "payment_options_interval_count_positive"
    t.check_constraint "price >= 0", name: "payment_options_price_non_negative"
    t.check_constraint "trial_days >= 0", name: "payment_options_trial_days_non_negative"
  end

  create_table "payment_engine_payments", force: :cascade do |t|
    t.bigint "purchase_id", null: false
    t.bigint "membership_id"
    t.string "provider", null: false
    t.string "provider_transaction_id"
    t.bigint "amount", default: 0, null: false
    t.string "currency", limit: 3, null: false
    t.string "status", default: "pending", null: false
    t.string "payment_method"
    t.datetime "paid_at"
    t.text "failure_reason"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "membership_id" ], name: "index_payment_engine_payments_on_membership_id"
    t.index [ "provider", "provider_transaction_id" ], name: "index_payment_engine_payments_unique_provider_transaction", unique: true, where: "(provider_transaction_id IS NOT NULL)"
    t.index [ "purchase_id" ], name: "index_payment_engine_payments_on_purchase_id"
    t.index [ "status", "created_at" ], name: "index_payment_engine_payments_on_status_and_created_at"
    t.check_constraint "amount >= 0", name: "payments_amount_non_negative"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'approved'::character varying::text, 'rejected'::character varying::text, 'canceled'::character varying::text, 'refunded'::character varying::text, 'partially_refunded'::character varying::text])", name: "payments_status_valid"
  end

  create_table "payment_engine_provider_customers", force: :cascade do |t|
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.string "provider", null: false
    t.string "provider_customer_id", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "owner_type", "owner_id", "provider" ], name: "index_payment_engine_provider_customers_unique_owner", unique: true
    t.index [ "owner_type", "owner_id" ], name: "idx_on_owner_type_owner_id_a490115f8f"
    t.index [ "provider", "provider_customer_id" ], name: "index_payment_engine_provider_customers_unique_provider_id", unique: true
  end

  create_table "payment_engine_purchases", force: :cascade do |t|
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.bigint "payment_option_id", null: false
    t.bigint "membership_id"
    t.string "status", default: "pending", null: false
    t.bigint "amount", default: 0, null: false
    t.string "currency", limit: 3, null: false
    t.string "provider"
    t.string "description"
    t.datetime "purchased_at"
    t.string "option_name"
    t.string "membership_type_name"
    t.bigint "price"
    t.jsonb "duration", default: {}, null: false
    t.string "billing_type"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "membership_id" ], name: "index_payment_engine_purchases_on_membership_id"
    t.index [ "owner_type", "owner_id" ], name: "index_payment_engine_purchases_on_owner_type_and_owner_id"
    t.index [ "payment_option_id" ], name: "index_payment_engine_purchases_on_payment_option_id"
    t.index [ "provider" ], name: "index_payment_engine_purchases_on_provider"
    t.index [ "status", "created_at" ], name: "index_payment_engine_purchases_on_status_and_created_at"
    t.check_constraint "amount >= 0", name: "purchases_amount_non_negative"
    t.check_constraint "price IS NULL OR price >= 0", name: "purchases_price_non_negative"
    t.check_constraint "status::text = ANY (ARRAY['pending'::character varying::text, 'processing'::character varying::text, 'completed'::character varying::text, 'failed'::character varying::text, 'canceled'::character varying::text, 'refunded'::character varying::text])", name: "purchases_status_valid"
  end

  create_table "payment_engine_subscriptions", force: :cascade do |t|
    t.bigint "membership_id", null: false
    t.bigint "payment_option_id", null: false
    t.string "provider", null: false
    t.string "provider_subscription_id"
    t.string "status", default: "active", null: false
    t.bigint "price", default: 0, null: false
    t.string "currency", limit: 3, null: false
    t.string "billing_type"
    t.jsonb "duration", default: {}, null: false
    t.datetime "current_period_starts_at"
    t.datetime "current_period_ends_at"
    t.datetime "next_billing_at"
    t.boolean "cancel_at_period_end", default: false, null: false
    t.datetime "canceled_at"
    t.datetime "trial_ends_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "membership_id" ], name: "index_payment_engine_subscriptions_on_membership_id"
    t.index [ "payment_option_id" ], name: "index_payment_engine_subscriptions_on_payment_option_id"
    t.index [ "provider", "provider_subscription_id" ], name: "index_payment_engine_subscriptions_unique_provider_id", unique: true, where: "(provider_subscription_id IS NOT NULL)"
    t.index [ "status", "next_billing_at" ], name: "idx_on_status_next_billing_at_6c09dfc376"
    t.check_constraint "price >= 0", name: "subscriptions_price_non_negative"
    t.check_constraint "status::text = ANY (ARRAY['trialing'::character varying::text, 'active'::character varying::text, 'past_due'::character varying::text, 'paused'::character varying::text, 'canceled'::character varying::text, 'expired'::character varying::text])", name: "subscriptions_status_valid"
  end

  create_table "payment_engine_webhook_events", force: :cascade do |t|
    t.string "provider", null: false
    t.string "event_id", null: false
    t.string "event_type"
    t.jsonb "payload", default: {}, null: false
    t.string "status", default: "received", null: false
    t.datetime "received_at", null: false
    t.datetime "processed_at"
    t.text "error_message"
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "provider", "event_id" ], name: "index_payment_engine_webhook_events_on_provider_and_event_id", unique: true
    t.index [ "status", "received_at" ], name: "index_payment_engine_webhook_events_on_status_and_received_at"
    t.check_constraint "status::text = ANY (ARRAY['received'::character varying::text, 'processing'::character varying::text, 'processed'::character varying::text, 'failed'::character varying::text, 'ignored'::character varying::text])", name: "webhook_events_status_valid"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "email" ], name: "index_users_on_email", unique: true
  end

  add_foreign_key "payment_engine_memberships", "payment_engine_membership_types", column: "membership_type_id"
  add_foreign_key "payment_engine_memberships", "payment_engine_payment_options", column: "payment_option_id"
  add_foreign_key "payment_engine_payment_options", "payment_engine_membership_types", column: "membership_type_id"
  add_foreign_key "payment_engine_payments", "payment_engine_memberships", column: "membership_id"
  add_foreign_key "payment_engine_payments", "payment_engine_purchases", column: "purchase_id"
  add_foreign_key "payment_engine_purchases", "payment_engine_memberships", column: "membership_id"
  add_foreign_key "payment_engine_purchases", "payment_engine_payment_options", column: "payment_option_id"
  add_foreign_key "payment_engine_subscriptions", "payment_engine_memberships", column: "membership_id"
  add_foreign_key "payment_engine_subscriptions", "payment_engine_payment_options", column: "payment_option_id"
end
