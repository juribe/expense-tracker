# frozen_string_literal: true

require "test_helper"

class EncryptionBackfillTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Backfill User", email: "backfill@example.com", password: "password123")
  end

  test "detects and re-encrypts plaintext values" do
    credential = @user.create_totp_credential!(secret: TotpCredential.generate_secret)
    TotpCredential.where(id: credential.id).update_all([ "secret = ?", "LEGACY-PLAINTEXT" ])

    rows = EncryptionBackfill.plaintext_rows
    assert rows.any? { |row| row[:record].id == credential.id && row[:attribute] == "secret" }

    previous = ActiveRecord::Encryption.config.support_unencrypted_data
    begin
      ActiveRecord::Encryption.config.support_unencrypted_data = true
      EncryptionBackfill.run!
    ensure
      ActiveRecord::Encryption.config.support_unencrypted_data = previous
    end

    raw = credential.reload.read_attribute_before_type_cast(:secret)
    refute_includes raw, "LEGACY"
    assert_equal "LEGACY-PLAINTEXT", credential.secret
  end

  test "reading a plaintext value fails when support is disabled" do
    credential = @user.create_totp_credential!(secret: TotpCredential.generate_secret)
    TotpCredential.where(id: credential.id).update_all([ "secret = ?", "LEGACY-PLAINTEXT" ])

    assert_raises(ActiveRecord::Encryption::Errors::Decryption) { credential.reload.secret }
  end

  test "does not flag rows that are already encrypted" do
    credential = @user.create_totp_credential!(secret: TotpCredential.generate_secret)

    rows = EncryptionBackfill.plaintext_rows

    refute rows.any? { |row| row[:record].id == credential.id }
  end
end
