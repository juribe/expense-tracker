module PaymentEngine
  class ApplicationJob < ActiveJob::Base
    queue_as :default

    # Retries are safe because every financial operation is idempotent.
    retry_on StandardError, wait: :polynomially_longer, attempts: 5
  end
end
