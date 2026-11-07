# frozen_string_literal: true

class WebauthnCredential < ApplicationRecord
  # A WebAuthn credential registered by a user. first_factor credentials are
  # passkeys used to sign in; second_factor credentials are security keys used
  # after the password.
  belongs_to :user

  validates :external_id, :public_key, :name, :sign_count, presence: true
  validates :external_id, uniqueness: true

  enum :authentication_factor, { first_factor: 0, second_factor: 1 }

  scope :passkey, -> { first_factor }
end
