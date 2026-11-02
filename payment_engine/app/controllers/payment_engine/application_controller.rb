# frozen_string_literal: true

module PaymentEngine
  class ApplicationController < ::ActionController::Base
    helper PaymentEngine::ApplicationHelper
    protect_from_forgery with: :exception
    helper_method :current_host_user, :payment_engine_owner_label

    def current_host_user
      cfg = PaymentEngine.configuration
      cfg.current_user.call(self)
    rescue
      nil
    end

    def payment_engine_owner_label(owner)
      PaymentEngine.configuration.owner_resolver.call(owner)[:label]
    rescue
      "#{owner.class}##{owner.id}"
    end
  end
end
