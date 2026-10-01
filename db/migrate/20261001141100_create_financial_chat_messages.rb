class CreateFinancialChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table "financial_chat_messages", force: :cascade do |t|
      t.references "financial_chat", null: false, foreign_key: true
      t.string "role", null: false
      t.text "content", null: false
      t.string "status", default: "complete", null: false
      t.string "error_message"
      t.string "model"
      t.integer "input_tokens"
      t.integer "output_tokens"
      t.integer "latency_ms"
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end

    add_index "financial_chat_messages", [ "financial_chat_id", "created_at" ],
              name: "index_financial_chat_messages_on_chat_id_and_created_at"
  end
end
