# Converts every MoneySourceTag into a MoneySourceRecognitionIdentifier of
# kind "keyword" (deduped per source), then drops the tags table — tags are
# fully superseded by Source Recognition.
class MigrateTagsToRecognitionIdentifiers < ActiveRecord::Migration[8.0]
  class MigrationTag < ActiveRecord::Base
    self.table_name = "money_source_tags"
  end

  class MigrationRecognition < ActiveRecord::Base
    self.table_name = "money_source_recognitions"
  end

  class MigrationIdentifier < ActiveRecord::Base
    self.table_name = "money_source_recognition_identifiers"
  end

  def up
    MigrationTag.order(:money_source_id, :id).find_each do |tag|
      recognition = MigrationRecognition.find_or_create_by!(money_source_id: tag.money_source_id)
      next_position = MigrationIdentifier
                      .where(money_source_recognition_id: recognition.id)
                      .maximum(:position).to_i + 1

      MigrationIdentifier.find_or_create_by!(
        money_source_recognition_id: recognition.id,
        kind: "keyword",
        value: tag.value
      ) do |identifier|
        identifier.position = next_position
      end
    end

    drop_table :money_source_tags
  end

  def down
    create_table :money_source_tags do |t|
      t.bigint :money_source_id, null: false
      t.string :value, null: false
      t.timestamps
    end
    add_index :money_source_tags, [ :money_source_id, :value ], unique: true
    add_index :money_source_tags, :money_source_id
    add_index :money_source_tags, :value
    # Data conversion is not reversible: previously migrated tags now live as
    # keyword recognition identifiers.
  end
end
