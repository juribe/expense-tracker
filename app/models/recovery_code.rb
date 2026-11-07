# frozen_string_literal: true

# One-time recovery codes for MFA (WebAuthn security keys or TOTP).
#
# Codes are shown once at generation time and only their bcrypt digests are
# persisted. Normalization (case and separators) is applied both when hashing
# and when consuming, so users can type them with or without hyphens.
class RecoveryCode < ApplicationRecord
  CODE_COUNT = 10
  CODE_BYTES = 10
  NORMALIZER = /[^a-z0-9]/

  belongs_to :user

  validates :code_digest, presence: true

  scope :unused, -> { where(used_at: nil) }

  class << self
    # Replaces every existing code for the user and returns the plaintext
    # codes in display order. Old codes stop working immediately.
    def generate_for(user, count: CODE_COUNT)
      plaintext_codes = Array.new(count) { generate_code }

      user.with_lock do
        user.recovery_codes.delete_all
        plaintext_codes.each do |code|
          user.recovery_codes.create!(code_digest: digest(code))
        end
      end

      plaintext_codes
    end

    # Consumes an unused code and returns its record. Returns nil when the code
    # is blank, unknown, already used, or belongs to another user. The final
    # update is conditional so two concurrent requests cannot both consume the
    # same code.
    def consume!(user, plaintext_code)
      normalized_code = normalize(plaintext_code)
      return nil if normalized_code.blank?

      user.recovery_codes.unused.find_each do |recovery_code|
        next unless matches?(recovery_code, normalized_code)

        consumed = user.recovery_codes.unused.where(id: recovery_code.id).update_all(used_at: Time.current)
        return recovery_code.reload if consumed == 1
      end

      nil
    rescue BCrypt::Errors::InvalidHash, ActiveRecord::RecordNotFound
      nil
    end

    private

    def matches?(recovery_code, normalized_code)
      BCrypt::Password.new(recovery_code.code_digest).is_password?(normalized_code)
    end

    def digest(code)
      BCrypt::Password.create(normalize(code), cost: bcrypt_cost)
    end

    def normalize(code)
      compact = code.to_s.downcase.gsub(NORMALIZER, "")
      compact.scan(/.{1,5}/).join("-")
    end

    def generate_code
      SecureRandom.hex(CODE_BYTES).scan(/.{5}/).join("-")
    end

    def bcrypt_cost
      Rails.env.test? ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost
    end
  end
end
