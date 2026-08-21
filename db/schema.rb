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

ActiveRecord::Schema[8.0].define(version: 2026_08_21_000200) do
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

  create_table "recurring_transaction_occurrences", force: :cascade do |t|
    t.integer "recurring_transaction_id", null: false
    t.string "transaction_type", null: false
    t.integer "transaction_id", null: false
    t.date "transaction_date", null: false
    t.string "period", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["recurring_transaction_id", "period"], name: "index_recurring_transactions_on_period", unique: true
    t.index ["recurring_transaction_id"], name: "idx_on_recurring_transaction_id_50fae07783"
    t.index ["transaction_type", "transaction_id"], name: "index_recurring_transaction_occurrences_on_transaction"
  end

  create_table "recurring_transactions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "category_id", null: false
    t.string "transaction_type", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "description"
    t.string "frequency", default: "monthly", null: false
    t.integer "payment_day"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_recurring_transactions_on_category_id"
    t.index ["transaction_type"], name: "index_recurring_transactions_on_transaction_type"
    t.index ["user_id"], name: "index_recurring_transactions_on_user_id"
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
  add_foreign_key "incomes", "categories"
  add_foreign_key "incomes", "users"
  add_foreign_key "recurring_transaction_occurrences", "recurring_transactions"
  add_foreign_key "recurring_transactions", "categories"
  add_foreign_key "recurring_transactions", "users"
end
