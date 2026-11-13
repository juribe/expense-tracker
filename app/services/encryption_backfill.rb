# frozen_string_literal: true

# Finds rows stored as plaintext in columns protected by Active Record
# Encryption (legacy rows written before encryption was enabled) and rewrites
# them as ciphertext. Run it before disabling support_unencrypted_data.
class EncryptionBackfill
  TARGETS = {
    "TotpCredential" => %w[secret],
    "WhatsappIdentity" => %w[phone_number],
    "ExpenseClarification" => %w[phone_number],
    "PaymentEngine::Provider" => %w[credentials settings]
  }.freeze

  class << self
    # Returns [{ model:, record:, attribute:, raw: }] for plaintext values.
    def plaintext_rows
      TARGETS.flat_map do |model_name, attributes|
        model = model_name.constantize
        attributes.flat_map do |attribute|
          model.where.not(attribute => [ nil, "" ]).find_each.filter_map do |record|
            raw = record.read_attribute_before_type_cast(attribute)
            { model: model, record: record, attribute: attribute, raw: raw } unless encrypted_value?(raw)
          end
        end
      end
    end

    # Re-encrypts every plaintext value. Requires support_unencrypted_data to
    # read the legacy value through the model.
    def run!
      rows = plaintext_rows
      rows.each do |row|
        record = row[:record]
        attribute = row[:attribute]
        # Assignment would look unchanged (both sides cast to the same
        # plaintext), so serialize the ciphertext and write it raw.
        plaintext = record.public_send(attribute)
        ciphertext = record.class.type_for_attribute(attribute).serialize(plaintext)
        record.class.where(id: record.id).update_all(
          [ "#{record.class.connection.quote_column_name(attribute)} = ?", ciphertext ]
        )
      end
      rows.size
    end

    def encrypted_value?(raw)
      return true if raw.blank?

      ActiveRecord::Encryption::MessageSerializer.new.load(raw.to_s)
      true
    rescue ActiveRecord::Encryption::Errors::Base, JSON::ParserError, TypeError
      false
    end
  end
end
