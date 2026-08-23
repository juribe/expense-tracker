# frozen_string_literal: true

# Encrypts model attributes at rest using ActiveSupport::MessageEncryptor with
# a key derived from the application secret. Used for OAuth credentials that
# must never be stored in plain text.
module EncryptedSecret
  extend ActiveSupport::Concern

  class_methods do
    def encrypts_secret(attribute)
      define_method(attribute) { decrypt_secret(self[attribute]) }
      define_method("#{attribute}=") { |value| self[attribute] = encrypt_secret(value) }
    end

    def secret_encryptor
      @secret_encryptor ||= begin
        key = Rails.application.key_generator.generate_key("#{name.underscore}/secrets", 32)
        ActiveSupport::MessageEncryptor.new(key)
      end
    end
  end

  private

  def encrypt_secret(value)
    return if value.blank?

    self.class.secret_encryptor.encrypt_and_sign(value.to_s)
  end

  def decrypt_secret(value)
    return if value.blank?

    self.class.secret_encryptor.decrypt_and_verify(value)
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ArgumentError
    nil
  end
end
