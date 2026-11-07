# frozen_string_literal: true

class Users::PasskeyAuthenticationOptionsController < Devise::PasskeyAuthenticationOptionsController
  def create
    session[:authentication_challenge_at] = Time.current.to_i
    super
  end
end
