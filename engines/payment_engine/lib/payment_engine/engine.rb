module PaymentEngine
  class Engine < ::Rails::Engine
    isolate_namespace PaymentEngine

    config.generators do |generators|
      generators.test_framework :minitest
      generators.helper false
      generators.assets false
    end
  end
end
