class AddUniqueExternalReferenceToPaymentEnginePayments < ActiveRecord::Migration[8.1]
  def change
    add_index :payment_engine_payments, :external_reference,
              unique: true,
              where: "external_reference IS NOT NULL AND external_reference <> ''",
              name: "index_payment_engine_payments_on_external_reference"
  end
end
