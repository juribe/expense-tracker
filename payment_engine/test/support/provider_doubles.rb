module ProviderDoubles
  class Limited < PaymentEngine::Providers::Base
    def self.capabilities
      %i[payments]
    end

    def create_payment(purchase:, payment:, **)
      PaymentEngine::Result.success(
        data: { provider_transaction_id: "limited-#{purchase.id}", checkout: { url: "https://limited.test/#{purchase.id}" } }
      )
    end
  end

  class Failing < PaymentEngine::Providers::Base
    def self.capabilities
      %i[payments]
    end

    def create_payment(purchase:, payment:, **)
      PaymentEngine::Result.failure(code: :provider_declined, errors: ["provider declined the operation"])
    end
  end

  class Raising < PaymentEngine::Providers::Base
    def self.capabilities
      %i[payments]
    end

    def create_payment(purchase:, payment:, **)
      raise "connection reset"
    end
  end
end

PaymentEngine.providers.register(:limited, ProviderDoubles::Limited)
PaymentEngine.providers.register(:failing, ProviderDoubles::Failing)
PaymentEngine.providers.register(:raising, ProviderDoubles::Raising)
