# frozen_string_literal: true

# Recognition identifiers now carry a lifecycle state:
#   status  - "confirmed" (user accepted, used for matching) or "suggested"
#             (discovered, awaiting user review; never used for matching).
#   origin  - where the value came from: "user" (typed/accepted on the
#             recognition page) or "gmail" (discovered during a Gmail sync).
#   observation_count / last_seen_at - recurring-discovery bookkeeping for
#             suggested values across incremental syncs.
class AddDiscoveryStateToRecognitionIdentifiers < ActiveRecord::Migration[8.0]
  def change
    add_column :money_source_recognition_identifiers, :status, :string, null: false, default: "confirmed"
    add_column :money_source_recognition_identifiers, :origin, :string, null: false, default: "user"
    add_column :money_source_recognition_identifiers, :observation_count, :integer, null: false, default: 1
    add_column :money_source_recognition_identifiers, :last_seen_at, :datetime
    add_index :money_source_recognition_identifiers, :status
  end
end
