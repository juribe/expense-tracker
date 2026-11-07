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

  unless Devise::Strategies::WebauthnTwoFactorAuthenticatable.ancestors.include?(YogastoTwoFactorChallengeExpiryGuard)
    Devise::Strategies::WebauthnTwoFactorAuthenticatable.prepend(YogastoTwoFactorChallengeExpiryGuard)
  end
end
