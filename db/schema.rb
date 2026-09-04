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

ActiveRecord::Schema[8.0].define(version: 2026_09_04_000002) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "categories", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug", null: false
    t.bigint "parent_id"
    t.boolean "active", default: true, null: false
    t.string "image"
    t.bigint "user_id"
    t.boolean "is_default", default: false, null: false
    t.string "category_type"
    t.index ["category_type"], name: "index_categories_on_category_type"
    t.index ["is_default"], name: "index_categories_on_is_default"
    t.index ["name"], name: "index_categories_on_name"
    t.index ["parent_id"], name: "index_categories_on_parent_id"
    t.index ["slug"], name: "index_categories_on_slug"
    t.index ["user_id"], name: "index_categories_on_user_id"
  end

  create_table "credit_accounts", force: :cascade do |t|
    t.bigint "money_source_id", null: false
    t.decimal "credit_limit", precision: 14, scale: 2
    t.decimal "interest_rate", precision: 8, scale: 4
    t.string "interest_rate_type"
    t.string "card_brand"
    t.string "card_last_four"
    t.integer "statement_day"
    t.integer "payment_due_day"
    t.decimal "principal_amount", precision: 14, scale: 2
    t.decimal "outstanding_balance", precision: 14, scale: 2
    t.decimal "installment_amount", precision: 14, scale: 2
    t.integer "installment_count"
    t.string "payment_frequency"
    t.date "start_date"
    t.date "end_date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "installments_paid"
    t.index ["money_source_id"], name: "index_credit_accounts_on_money_source_id", unique: true
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

  create_table "financial_institutions", force: :cascade do |t|
    t.string "canonical_name", null: false
    t.jsonb "aliases", default: [], null: false
    t.jsonb "domains", default: [], null: false
    t.jsonb "keywords", default: [], null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_name"], name: "index_financial_institutions_on_canonical_name", unique: true
  end

  create_table "financial_keywords", force: :cascade do |t|
    t.string "value", null: false
    t.string "category", null: false
    t.integer "weight", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_financial_keywords_on_category"
    t.index ["value"], name: "index_financial_keywords_on_value", unique: true
  end

  create_table "financial_setups", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "current_step", default: 0, null: false
    t.string "status", default: "in_progress", null: false
    t.jsonb "data", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "status"], name: "index_financial_setups_on_user_id_and_status"
    t.index ["user_id"], name: "index_financial_setups_on_user_id"
  end

  create_table "financial_subject_patterns", force: :cascade do |t|
    t.string "value", null: false
    t.integer "weight", default: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["value"], name: "index_financial_subject_patterns_on_value", unique: true
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
    t.datetime "syncing"
    t.json "last_sync_summary"
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

  create_table "money_source_recognition_identifiers", force: :cascade do |t|
    t.bigint "money_source_recognition_id", null: false
    t.string "kind", null: false
    t.string "value", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "confirmed", null: false
    t.string "origin", default: "user", null: false
    t.integer "observation_count", default: 1, null: false
    t.datetime "last_seen_at"
    t.index ["money_source_recognition_id", "kind", "position"], name: "index_mrs_identifiers_on_recognition_kind_position"
    t.index ["money_source_recognition_id", "kind", "value"], name: "index_mrs_identifiers_on_recognition_kind_value", unique: true
    t.index ["money_source_recognition_id"], name: "idx_on_money_source_recognition_id_39b1679ecd"
    t.index ["status"], name: "index_money_source_recognition_identifiers_on_status"
  end

  create_table "money_source_recognitions", force: :cascade do |t|
    t.bigint "money_source_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["money_source_id"], name: "index_money_source_recognitions_on_money_source_id", unique: true
  end

  create_table "money_sources", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "kind", null: false
    t.string "bank"
    t.integer "parent_id"
    t.decimal "starting_balance", precision: 12, scale: 2, default: "0.0", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "identifier"
    t.index ["parent_id"], name: "index_money_sources_on_parent_id"
    t.index ["user_id", "identifier"], name: "index_money_sources_on_user_id_and_identifier", unique: true
    t.index ["user_id", "kind"], name: "index_money_sources_on_user_id_and_kind"
    t.index ["user_id"], name: "index_money_sources_on_user_id"
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
    t.integer "money_source_id"
    t.index ["category_id"], name: "index_recurring_templates_on_category_id"
    t.index ["kind"], name: "index_recurring_templates_on_kind"
    t.index ["money_source_id"], name: "index_recurring_templates_on_money_source_id"
    t.index ["user_id", "kind"], name: "index_recurring_templates_on_user_id_and_kind"
    t.index ["user_id"], name: "index_recurring_templates_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.string "concurrency_key", null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.text "error"
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "queue_name", null: false
    t.string "class_name", null: false
    t.text "arguments"
    t.integer "priority", default: 0, null: false
    t.string "active_job_id"
    t.datetime "scheduled_at"
    t.datetime "finished_at"
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.string "queue_name", null: false
    t.datetime "created_at", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.bigint "supervisor_id"
    t.integer "pid", null: false
    t.string "hostname"
    t.text "metadata"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "task_key", null: false
    t.datetime "run_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.string "key", null: false
    t.string "schedule", null: false
    t.string "command", limit: 2048
    t.string "class_name"
    t.text "arguments"
    t.string "queue_name"
    t.integer "priority", default: 0
    t.boolean "static", default: true, null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.bigint "job_id", null: false
    t.string "queue_name", null: false
    t.integer "priority", default: 0, null: false
    t.datetime "scheduled_at", null: false
    t.datetime "created_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.string "key", null: false
    t.integer "value", default: 1, null: false
    t.datetime "expires_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
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
    t.integer "money_source_id"
    t.index ["category_id"], name: "index_transactions_on_category_id"
    t.index ["date"], name: "index_transactions_on_date"
    t.index ["gmail_message_id"], name: "index_transactions_on_gmail_message_id"
    t.index ["kind"], name: "index_transactions_on_kind"
    t.index ["money_source_id"], name: "index_transactions_on_money_source_id"
    t.index ["recurring_template_id"], name: "index_transactions_on_recurring_template_id"
    t.index ["user_id", "kind", "date"], name: "index_transactions_on_user_id_and_kind_and_date"
    t.index ["user_id"], name: "index_transactions_on_user_id"
  end

  create_table "transfers", force: :cascade do |t|
    t.integer "user_id", null: false
    t.integer "from_source_id", null: false
    t.integer "to_source_id", null: false
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.date "date", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["from_source_id"], name: "index_transfers_on_from_source_id"
    t.index ["to_source_id"], name: "index_transfers_on_to_source_id"
    t.index ["user_id", "date"], name: "index_transfers_on_user_id_and_date"
    t.index ["user_id"], name: "index_transfers_on_user_id"
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

  add_foreign_key "categories", "users"
  add_foreign_key "credit_accounts", "money_sources"
  add_foreign_key "expenses", "categories"
  add_foreign_key "expenses", "users"
  add_foreign_key "financial_setups", "users"
  add_foreign_key "gmail_connections", "users"
  add_foreign_key "incomes", "categories"
  add_foreign_key "incomes", "users"
  add_foreign_key "money_source_recognition_identifiers", "money_source_recognitions"
  add_foreign_key "money_source_recognitions", "money_sources"
  add_foreign_key "money_sources", "money_sources", column: "parent_id"
  add_foreign_key "money_sources", "users"
  add_foreign_key "processed_emails", "transactions", column: "expense_id"
  add_foreign_key "processed_emails", "users"
  add_foreign_key "recurring_templates", "categories"
  add_foreign_key "recurring_templates", "money_sources"
  add_foreign_key "recurring_templates", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "transactions", "categories"
  add_foreign_key "transactions", "money_sources"
  add_foreign_key "transactions", "recurring_templates"
  add_foreign_key "transactions", "users"
  add_foreign_key "transfers", "money_sources", column: "from_source_id"
  add_foreign_key "transfers", "money_sources", column: "to_source_id"
  add_foreign_key "transfers", "users"
end
