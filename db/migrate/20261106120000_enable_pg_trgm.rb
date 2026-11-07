# frozen_string_literal: true

# Enables trigram indexes used by the help center search.
class EnablePgTrgm < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"
  end
end
