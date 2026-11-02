# frozen_string_literal: true

module PaymentEngine
  class Engine < ::Rails::Engine
    isolate_namespace PaymentEngine

    config.generators do |g|
      g.test_framework :minitest, fixture: false
      g.fixture_replacement :none
    end

    initializer "payment_engine.assets" do |app|
      # ensure engine assets are available
    end

    initializer "payment_engine.migrations" do |app|
      # allow host to copy migrations via railties
    end
  end
end
