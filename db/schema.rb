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

ActiveRecord::Schema[8.0].define(version: 2026_08_23_000003) do
  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug", null: false
    t.bigint "parent_id"
    t.boolean "active", default: true, null: false
    t.string "image"
    t.index ["name"], name: "index_categories_on_name", unique: true
    t.index ["parent_id"], name: "index_categories_on_parent_id"
    t.index ["slug"], name: "index_categories_on_slug", unique: true
  end

  create_table "expenses", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "category_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "description"
    t.date "date", null: false
    t.string "frequency", default: "one_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_expenses_on_category_id"
    t.index ["user_id"], name: "index_expenses_on_user_id"
  end

  create_table "gmail_connections", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "email", null: false
    t.string "google_account_id"
    t.string "access_token"
    t.string "refresh_token"
    t.datetime "token_expires_at"
    t.json "search_config", default: {}
    t.datetime "last_synced_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "email"], name: "index_gmail_connections_on_user_id_and_email", unique: true
    t.index ["user_id"], name: "index_gmail_connections_on_user_id"
  end

  create_table "incomes", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "category_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "description"
    t.date "date", null: false
    t.string "frequency", default: "one_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_incomes_on_category_id"
    t.index ["user_id"], name: "index_incomes_on_user_id"
  end

  create_table "processed_emails", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "expense_id"
    t.string "provider", default: "gmail", null: false
    t.string "message_id", null: false
    t.string "status", default: "processed", null: false
    t.text "payload"
    t.string "failure_reason"
    t.integer "attempts", default: 0, null: false
    t.datetime "processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expense_id"], name: "index_processed_emails_on_expense_id"
    t.index ["provider", "message_id"], name: "index_processed_emails_on_provider_and_message_id", unique: true
    t.index ["status"], name: "index_processed_emails_on_status"
    t.index ["user_id"], name: "index_processed_emails_on_user_id"
  end

  create_table "recurring_templates", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "category_id", null: false
    t.string "kind", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "description"
    t.integer "payment_day"
    t.string "frequency", default: "monthly", null: false
    t.boolean "active", default: true, null: false
    t.string "source", default: "manual", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_recurring_templates_on_category_id"
    t.index ["kind"], name: "index_recurring_templates_on_kind"
    t.index ["user_id", "kind"], name: "index_recurring_templates_on_user_id_and_kind"
    t.index ["user_id"], name: "index_recurring_templates_on_user_id"
  end

  create_table "transactions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "category_id", null: false
    t.date "date", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "kind", null: false
    t.string "description"
    t.string "source", default: "manual", null: false
    t.integer "recurring_template_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "gmail_message_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["date"], name: "index_transactions_on_date"
    t.index ["gmail_message_id"], name: "index_transactions_on_gmail_message_id"
    t.index ["kind"], name: "index_transactions_on_kind"
    t.index ["recurring_template_id"], name: "index_transactions_on_recurring_template_id"
    t.index ["user_id", "kind", "date"], name: "index_transactions_on_user_id_and_kind_and_date"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "expenses", "categories"
  add_foreign_key "expenses", "users"
  add_foreign_key "gmail_connections", "users"
  add_foreign_key "incomes", "categories"
  add_foreign_key "incomes", "users"
  add_foreign_key "processed_emails", "transactions", column: "expense_id"
  add_foreign_key "processed_emails", "users"
  add_foreign_key "recurring_templates", "categories"
  add_foreign_key "recurring_templates", "users"
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "recurring_templates"
  add_foreign_key "transactions", "users"
end
