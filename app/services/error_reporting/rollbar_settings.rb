# frozen_string_literal: true

# RollbarSettings
# Resolves Rollbar configuration from environment variables and Rails filters.
#
# Example:
#   ErrorReporting::RollbarSettings.new.enabled? # => true in production with a token
module ErrorReporting
  class RollbarSettings
    ENABLED_ENVIRONMENTS = %w[production staging].freeze

    DEFAULT_SCRUB_FIELDS = %i[
      passw password password_confirmation confirm_password current_password password_digest
      secret secret_token token access_token refresh_token auth_token api_key apikey
      authorization cookie cookies session session_id csrf authenticity_token
      email email_address phone phone_number mobile address ssn
      cvv cvc card card_number card_last4 account account_number iban routing_number
      description content body body_text html text transcript raw_body payload headers
      response raw_response api_response external_response error_message last_error
      subject sender recipient bank_statement statement
      file files file_data image_data audio_data attachment attachments upload uploads
      amount balance total subtotal merchant category transaction expense income
      credit_limit interest_rate installment principal
      public_key public_key_credential recovery_code code_digest
      totp_code otp_code totp_secret
      whatsapp whatsapp_access_token whatsapp_token whatsapp_business_phone_number_id
      epayco epayco_api_key epayco_private_key epayco_customer_id epayco_p_key
      inbound_email inbound_email_secret inbound_email_token
    ].freeze

    SCRUB_HEADERS = %w[
      Authorization
      Cookie
      Set-Cookie
      Proxy-Authorization
      X-Api-Key
      X-Auth-Token
      X-Csrf-Token
      X-Forwarded-For
      X-Real-Ip
    ].freeze

    IGNORED_EXCEPTION_LEVELS = {
      "ActiveRecord::RecordNotFound" => "ignore",
      "AbstractController::ActionNotFound" => "ignore",
      "ActionController::RoutingError" => "ignore",
      "ActionController::ParameterMissing" => "ignore",
      "ActionController::BadRequest" => "ignore",
      "ActionController::InvalidAuthenticityToken" => "ignore",
      "ActionDispatch::Http::Parameters::ParseError" => "ignore"
    }.freeze

    def initialize(env: ENV, rails_env: Rails.env, filter_parameters: nil)
      @env = env
      @rails_env = rails_env.to_s
      @filter_parameters = filter_parameters || Rails.application.config.filter_parameters
    end

    def enabled?
      return false if temporarily_disabled?

      access_token.present? && ENABLED_ENVIRONMENTS.include?(rails_env)
    end

    def access_token
      env["ROLLBAR_ACCESS_TOKEN"].presence
    end

    def environment
      env["ROLLBAR_ENV"].presence || rails_env
    end

    def code_version
      env["APP_VERSION"].presence
    end

    def scrub_fields
      (DEFAULT_SCRUB_FIELDS + Array(filter_parameters)).filter_map do |field|
        field.to_sym if field.is_a?(String) || field.is_a?(Symbol)
      end.uniq
    end

    def scrub_headers
      SCRUB_HEADERS
    end

    def ignored_exception_levels
      IGNORED_EXCEPTION_LEVELS
    end

    def config_attributes
      {
        enabled: enabled?,
        access_token: access_token,
        environment: environment,
        code_version: code_version,
        capture_uncaught: true,
        person_method: "current_user",
        person_id_method: "id",
        person_username_method: nil,
        person_email_method: nil,
        collect_user_ip: false,
        send_extra_frame_data: :none,
        scrub_fields: scrub_fields,
        scrub_headers: scrub_headers,
        log_payload: false,
        safely: true,
        use_exception_level_filters_default: true,
        disable_action_mailer_monkey_patch: true,
        enable_rails_error_subscriber: enabled?
      }
    end

    private

    attr_reader :env, :rails_env, :filter_parameters

    def temporarily_disabled?
      %w[false 0 no off].include?(env["ROLLBAR_ENABLED"].to_s.strip.downcase)
    end
  end
end
