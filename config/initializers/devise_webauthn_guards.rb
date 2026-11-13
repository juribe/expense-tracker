# frozen_string_literal: true

# Adds account-status and challenge-expiry guards to devise-webauthn's
# strategies without forking the gem.
Rails.application.config.to_prepare do
  require "devise/strategies/passkey_authenticatable"
  require "devise/strategies/webauthn_two_factor_authenticatable"

  module YogastoPasskeyAccountStatusGuard
    def success!(resource, *args)
      return fail!(:inactive) unless resource.active_for_authentication?

      super
    end
  end

  module YogastoPasskeyChallengeExpiryGuard
    def authenticate!
      if session[:authentication_challenge].present? &&
         !WebauthnChallenge.fresh?(session[:authentication_challenge_at])
        session.delete(:authentication_challenge)
        session.delete(:authentication_challenge_at)
        return fail!(:webauthn_challenge_expired)
      end

      super
    end
  end

  # The gem looks the assertion up in every WebAuthn credential, so a passkey
  # (first factor) could satisfy the second factor. Restrict the lookup to the
  # account's second-factor credentials before delegating to the strategy.
  module YogastoTwoFactorCredentialScopeGuard
    def authenticate!
      resource = resource_class.find_by(id: session[:current_authentication_resource_id])
      credential_id = parsed_credential_id

      if resource && credential_id.present? &&
         !resource.second_factor_webauthn_credentials.exists?(external_id: credential_id)
        return fail!(:webauthn_credential_not_found)
      end

      super
    end

    private

    def parsed_credential_id
      parsed = JSON.parse(params[:public_key_credential].to_s)
      parsed["id"] if parsed.is_a?(Hash)
    rescue JSON::ParserError, TypeError
      nil
    end
  end

  module YogastoTwoFactorChallengeExpiryGuard
    def authenticate!
      if session[:two_factor_authentication_challenge].present? &&
         !WebauthnChallenge.fresh?(session[:two_factor_authentication_challenge_at])
        session.delete(:two_factor_authentication_challenge)
        session.delete(:two_factor_authentication_challenge_at)
        return fail!(:webauthn_challenge_expired)
      end

      super
    end
  end

  unless Devise::Strategies::PasskeyAuthenticatable.ancestors.include?(YogastoPasskeyAccountStatusGuard)
    Devise::Strategies::PasskeyAuthenticatable.prepend(YogastoPasskeyAccountStatusGuard)
  end

  unless Devise::Strategies::PasskeyAuthenticatable.ancestors.include?(YogastoPasskeyChallengeExpiryGuard)
    Devise::Strategies::PasskeyAuthenticatable.prepend(YogastoPasskeyChallengeExpiryGuard)
  end

  unless Devise::Strategies::WebauthnTwoFactorAuthenticatable.ancestors.include?(YogastoTwoFactorCredentialScopeGuard)
    Devise::Strategies::WebauthnTwoFactorAuthenticatable.prepend(YogastoTwoFactorCredentialScopeGuard)
  end

  unless Devise::Strategies::WebauthnTwoFactorAuthenticatable.ancestors.include?(YogastoTwoFactorChallengeExpiryGuard)
    Devise::Strategies::WebauthnTwoFactorAuthenticatable.prepend(YogastoTwoFactorChallengeExpiryGuard)
  end
end
