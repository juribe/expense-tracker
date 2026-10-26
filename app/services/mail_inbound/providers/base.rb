# frozen_string_literal: true

module MailInbound
  module Providers
    class Base
      def valid_signature?(_request)
        raise NotImplementedError
      end

      def build_delivery(_request)
        raise NotImplementedError
      end

      def handle_email(_delivery)
        raise NotImplementedError
      end

      def provider_name
        raise NotImplementedError
      end

      def expense_source
        provider_name
      end
    end
  end
end
