class CreateFinancialChats < ActiveRecord::Migration[8.0]
  def change
    create_table "financial_chats", force: :cascade do |t|
      t.references "user", null: false, foreign_key: true, index: { unique: true }
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
    end
  end
end
