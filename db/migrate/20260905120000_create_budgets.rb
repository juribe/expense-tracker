class CreateBudgets < ActiveRecord::Migration[8.0]
  def change
    create_table :budgets do |t|
      t.references :user, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.decimal :monthly_amount, precision: 14, scale: 2, null: false
      t.string :period, default: "monthly", null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :budgets, [ :user_id, :category_id ], unique: true
  end
end
