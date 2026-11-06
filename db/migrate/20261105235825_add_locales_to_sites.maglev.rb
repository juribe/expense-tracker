# This migration comes from maglev (originally 20211008064437)
class AddLocalesToSites < ActiveRecord::Migration[6.0]
  def change
    change_table :maglev_sites do |t|
      if t.respond_to? :jsonb
        t.jsonb :locales, default: []
      elsif mysql?
        t.json :locales # MySQL doesn't support default values for json columns
      else
        t.json :locales, default: []
      end
    end
  end
end
