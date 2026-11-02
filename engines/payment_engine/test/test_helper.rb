# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
ActiveRecord::Migrator.migrations_paths << File.expand_path("../db/migrate", __dir__)
require "rails/test_help"

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [ File.expand_path("fixtures", __dir__) ]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end

PaymentEngine.reset_configuration!

PaymentEngine.configure do |config|
  config.default_provider = :fake
  config.membership_timezone = "UTC"
  config.expiration_grace_period_days = 0
  config.providers = {
    fake: { webhook_secret: "test-webhook-secret" },
    epayco: {
      public_key: "test-public-key",
      private_key: "test-private-key",
      customer_id: "123456",
      p_key: "test-p-key"
    }
  }
end

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |file| require file }
