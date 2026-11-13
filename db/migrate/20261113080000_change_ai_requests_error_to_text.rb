class ChangeAiRequestsErrorToText < ActiveRecord::Migration[8.1]
  def up
    change_column :ai_requests, :error, :text
  end

  def down
    change_column :ai_requests, :error, :string
  end
end
