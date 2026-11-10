PaymentEngine.configure do |config|
  # Provider used by Purchases::Create when no provider is passed explicitly.
  config.default_provider = :epayco

  # Provider credentials. Read them from environment variables or Rails credentials.
  config.providers = {
    epayco: {
      public_key: ENV["EPAYCO_PUBLIC_KEY"],
      private_key: ENV["EPAYCO_PRIVATE_KEY"],
      customer_id: ENV["EPAYCO_CUSTOMER_ID"],
      p_key: ENV["EPAYCO_P_KEY"],
      confirmation_url: "https://example.com/payment_engine/webhooks/epayco"
    }
  }

  # Presentation and calendar timezone. Timestamps are always stored in UTC.
  config.membership_timezone = "UTC"

  # Days of access granted after a failed recurring charge (0 disables grace).
  config.expiration_grace_period_days = 0

  # A full refund immediately revokes access. Partial refunds keep it.
  config.revoke_access_on_refund = true

  # Window used to reject accidental duplicate pending purchases per option.
  config.purchase_duplicate_window_minutes = 15
end
