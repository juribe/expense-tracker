# frozen_string_literal: true

# WebAuthn relying-party validation.
# The RP ID scopes passkeys to a domain. Browsers require it to be the origin
# host or one of its parent domains; a broader value widens credential scope
# and an unrelated value breaks registration/authentication.
module WebauthnConfig
  module_function

  def valid_rp_id?(host:, rp_id:)
    host = host.to_s.strip
    rp_id = rp_id.to_s.strip
    return false if host.blank? || rp_id.blank?
    return false if rp_id.include?("*") || rp_id.match?(/\s/)

    host == rp_id || host.end_with?(".#{rp_id}")
  end
end
