require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module ExpenseTracker
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1
    config.time_zone = "America/Bogota"

    # Use UUID primary keys for all new generated tables.
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    #
    # `will_paginate` holds our custom renderer. It reopens the `WillPaginate`
    # namespace provided by the gem, so it is loaded explicitly from
    # config/initializers/will_paginate.rb instead of being autoloaded.
    config.autoload_lib(ignore: %w[assets tasks will_paginate])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Single source of truth for the app's public hosts. Ops defines it in
    # production with RAILS_PUBLIC_HOSTS="domain.com,www..."; while unset it
    # falls back to expensetracker.com. Consumed by host protection in
    # production.rb and Action Cable request origins.
    public_hosts = ENV["RAILS_PUBLIC_HOSTS"].to_s.split(",").map(&:strip).compact_blank
    config.x.public_hosts = public_hosts.any? ? public_hosts : [ "expensetracker.com", "samyreplies.com" ]

    # Don't generate system test files.
    config.generators.system_tests = nil
  end
end
