require "rails/generators"
require "rails/generators/base"

module PaymentEngine
  module Generators
    # Installs the engine in a host application: initializer, mount point and
    # migrations. Authentication and authorization remain host responsibilities.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates the PaymentEngine initializer, mounts the engine and installs migrations"

      def copy_initializer
        template "initializer.rb", "config/initializers/payment_engine.rb"
      end

      def mount_engine
        routes_file = File.join(destination_root, "config/routes.rb")
        return if File.exist?(routes_file) && File.read(routes_file).include?("PaymentEngine::Engine")

        route 'mount PaymentEngine::Engine => "/payment_engine"'
      end

      def install_migrations
        rake "payment_engine:install:migrations"
      end
    end
  end
end
