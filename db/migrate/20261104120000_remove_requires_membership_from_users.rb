class RemoveRequiresMembershipFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :requires_membership, :boolean, default: false, null: false
  end
end
