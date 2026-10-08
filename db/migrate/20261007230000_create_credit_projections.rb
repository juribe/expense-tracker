class CreateCreditProjections < ActiveRecord::Migration[8.0]
  def change
    create_table :credit_projections do |t|
      t.references :money_source, null: false, foreign_key: true, index: { unique: true }
      t.boolean :estimated, default: false, null: false
      t.string :fingerprint, null: false
      t.jsonb :inputs, null: false, default: {}
      t.jsonb :schedule, null: false, default: {}
      t.jsonb :summary, null: false, default: {}
      t.jsonb :assumptions, null: false, default: []
      t.datetime :computed_at, null: false

      t.timestamps
    end
  end
end
