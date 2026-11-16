# frozen_string_literal: true

# Rollbar reports unexpected Rails and background job errors in production.
# The payload transform strips request data, job arguments and financial
# content before anything leaves the application.
#
# Configuration runs after initialization so the application classes that
# resolve settings and sanitize payloads are autoloaded normally.
Rails.application.config.after_initialize do
  settings = ErrorReporting::RollbarSettings.new

  Rollbar.configure do |config|
    settings.config_attributes.each do |name, value|
      config.public_send("#{name}=", value)
    end

    config.exception_level_filters.merge!(settings.ignored_exception_levels)
    config.transform = ->(options) { ErrorReporting::RollbarPayloadSanitizer.call(options) }
    config.use_thread if settings.enabled?
  end

  if Rails.env.production? && !settings.enabled?
    Rails.logger&.warn(
      "Rollbar is disabled: set ROLLBAR_ACCESS_TOKEN and leave ROLLBAR_ENABLED unset to enable error monitoring."
    )
  end

  if settings.enabled? && settings.code_version.blank?
    Rails.logger&.warn("APP_VERSION is unset: Rollbar reports will not identify the deployed revision.")
  end
end
