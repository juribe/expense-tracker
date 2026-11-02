module PaymentEngine
  module Providers
    # Registers adapter classes by name so host applications can switch payment
    # providers without touching domain models or services.
    class Registry
      def initialize
        @adapters = {}
      end

      def register(name, klass)
        unless klass.is_a?(Class) && klass <= Base
          raise ArgumentError, "#{klass.inspect} must inherit from PaymentEngine::Providers::Base"
        end

        @adapters[name.to_sym] = klass
      end

      def fetch(name)
        @adapters.fetch(name.to_sym) do
          raise UnknownProviderError, "Unknown payment provider: #{name}"
        end
      end

      def registered?(name)
        @adapters.key?(name.to_sym)
      end

      def names
        @adapters.keys
      end

      def reset!
        @adapters = {}
      end
    end
  end
end
