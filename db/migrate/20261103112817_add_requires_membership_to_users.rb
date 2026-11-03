class AddRequiresMembershipToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :requires_membership, :boolean, default: false, null: false
  end
end
