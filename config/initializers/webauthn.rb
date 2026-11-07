# frozen_string_literal: true

# WebAuthn relying-party configuration for Yogasto.
#
# Production and staging origins are explicit and must not use wildcards or
# plain HTTP. Override them with WEBAUTHN_ORIGIN (and optionally
# WEBAUTHN_RP_ID) per environment; development and test fall back to the
# local Rails server.
Rails.application.config.to_prepare do
  default_origin = Rails.env.production? ? "https://yogasto.co" : "http://localhost:3000"
  origin = ENV.fetch("WEBAUTHN_ORIGIN", default_origin).delete_suffix("/")

  if origin.include?("*")
    raise "WEBAUTHN_ORIGIN must be an explicit origin, not a wildcard (got #{origin.inspect})"
  end

  if Rails.env.production? && !origin.start_with?("https://")
    raise "WEBAUTHN_ORIGIN must use HTTPS in production (got #{origin.inspect})"
  end

  uri = URI.parse(origin)
  unless uri.is_a?(URI::HTTP) && uri.host.present?
    raise "WEBAUTHN_ORIGIN must be an absolute http(s) origin (got #{origin.inspect})"
  end

  if (uri.path.present? && uri.path != "/") || uri.query.present? || uri.fragment.present?
    raise "WEBAUTHN_ORIGIN must not include a path, query or fragment (got #{origin.inspect})"
  end

  normalized_origin = "#{uri.scheme}://#{uri.host}"
  normalized_origin += ":#{uri.port}" unless uri.port == uri.default_port
  rp_id = ENV["WEBAUTHN_RP_ID"].presence || uri.host

  WebAuthn.configure do |config|
    config.rp_name = "Yogasto"
    config.rp_id = rp_id
    config.allowed_origins = [ normalized_origin ]
    config.credential_options_timeout = 120_000
  end
end
