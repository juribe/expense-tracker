module PaymentEngine
  class ApplicationController < ActionController::Base
    # Host applications may override this hook to authorize engine endpoints.
    # Webhook authenticity is validated by the provider adapter, not by the host
    # authentication system.
    def payment_engine_authorized?
      true
    end
  end
end
