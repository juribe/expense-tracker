module PaymentEngine
  # Relationship between a host owner and a customer record in a payment
  # provider. Never stores full card numbers, CVV or authentication secrets.
  class ProviderCustomer < ApplicationRecord
    belongs_to :owner, polymorphic: true

    validates :provider, presence: true
    validates :provider_customer_id, presence: true, uniqueness: { scope: :provider }
    validates :provider, uniqueness: { scope: [ :owner_type, :owner_id ] }
  end
end
