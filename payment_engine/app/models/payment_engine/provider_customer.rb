# frozen_string_literal: true

module PaymentEngine
  class ProviderCustomer < ApplicationRecord
    belongs_to :owner, polymorphic: true
  end
end
