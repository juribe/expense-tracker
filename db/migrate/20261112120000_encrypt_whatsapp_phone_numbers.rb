# frozen_string_literal: true

# Re-encrypts stored WhatsApp numbers with Active Record Encryption and
# rewrites them to E.164. Existing plaintext rows are read through
# support_unencrypted_data and saved through the encrypted attribute, so no
# identity or clarification association is lost.
class EncryptWhatsappPhoneNumbers < ActiveRecord::Migration[8.1]
  def up
    previous_setting = ActiveRecord::Encryption.config.support_unencrypted_data
    ActiveRecord::Encryption.config.support_unencrypted_data = true

    ensure_no_identity_duplicates!
    rewrite!(WhatsappIdentity)
    rewrite!(ExpenseClarification)
  ensure
    ActiveRecord::Encryption.config.support_unencrypted_data = previous_setting
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Encrypted WhatsApp phone numbers cannot be decrypted automatically."
  end

  private

  def ensure_no_identity_duplicates!
    duplicates = WhatsappIdentity.pluck(:phone_number)
                                  .map { |number| WhatsappIdentity.normalize(number) }
                                  .tally
                                  .select { |_number, count| count > 1 }
    return if duplicates.empty?

    raise "WhatsApp identities would collide after E.164 normalization: #{duplicates.keys.join(', ')}"
  end

  def rewrite!(model)
    model.reset_column_information
    model.find_each do |record|
      record.phone_number = WhatsappIdentity.normalize(record.phone_number)
      record.phone_number_will_change!
      record.save!(validate: false)
    end
  end
end
