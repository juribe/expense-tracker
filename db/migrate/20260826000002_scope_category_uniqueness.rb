# frozen_string_literal: true

class ScopeCategoryUniqueness < ActiveRecord::Migration[8.0]
  def change
    # Remove the global unique constraints on name/slug. They prevented:
    #   - a default "Other" existing for both expense and income (identical slug/name)
    #   - different users having custom categories that share a name/slug
    # Uniqueness is now enforced per scope (default vs per-user custom) at the
    # model layer via unique_name_within_scope / unique_slug_within_scope.
    remove_index :categories, :slug
    remove_index :categories, :name

    add_index :categories, :slug
    add_index :categories, :name
  end
end
