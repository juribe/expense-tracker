class AddAccessDurationToPaymentOptions < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_engine_payment_options, :access_duration_count, :integer, default: 1, null: false
    add_column :payment_engine_payment_options, :access_duration_unit, :string, default: "month", null: false
  end
end
