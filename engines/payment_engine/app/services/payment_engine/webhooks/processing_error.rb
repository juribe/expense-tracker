module PaymentEngine
  module Webhooks
    # Raised when a provider event cannot be applied to the domain. Keeping it in
    # its own file lets Zeitwerk autoload it independently of Processor.
    class ProcessingError < StandardError; end
  end
end
