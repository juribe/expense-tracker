# frozen_string_literal: true

class CreateOnboardingProgresses < ActiveRecord::Migration[8.1]
  def change
    create_table :onboarding_progresses, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid :user_id, null: false
      t.jsonb :skipped_steps, default: [], null: false

      t.timestamps
    end

    add_index :onboarding_progresses, :user_id, unique: true
    add_foreign_key :onboarding_progresses, :users
  end
end
