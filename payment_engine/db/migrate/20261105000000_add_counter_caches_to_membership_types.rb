class AddCounterCachesToMembershipTypes < ActiveRecord::Migration[8.1]
  def change
    add_column :payment_engine_membership_types, :payment_options_count, :integer, default: 0, null: false
    add_column :payment_engine_membership_types, :memberships_count, :integer, default: 0, null: false

    reversible do |direction|
      direction.up do
        execute <<~SQL.squish
          UPDATE payment_engine_membership_types
          SET payment_options_count = (
                SELECT COUNT(*)
                FROM payment_engine_payment_options
                WHERE payment_engine_payment_options.membership_type_id = payment_engine_membership_types.id
              ),
              memberships_count = (
                SELECT COUNT(*)
                FROM payment_engine_memberships
                WHERE payment_engine_memberships.membership_type_id = payment_engine_membership_types.id
              )
        SQL
      end
    end
  end
end
