# Ensure URL helpers work in tests even when a test does not set a host.
Rails.application.routes.default_url_options[:host] = "example.com" if Rails.env.test?