# frozen_string_literal: true

# Splits the default "Comida y restaurantes" category into a "Comida" parent
# with a "Restaurante" shared subcategory, so restaurant/delivery expenses roll
# up into ["Comida", "Restaurante"] instead of a single catch-all bucket.
class SplitComidaYRestaurantesCategories < ActiveRecord::Migration[8.0]
  def up
    comida = Category.find_by(name: "Comida y restaurantes", is_default: true, category_type: "expense")
    comida&.update!(name: "Comida")

    comida = Category.find_by(name: "Comida", is_default: true, category_type: "expense")
    return if comida.nil?

    restaurante = Category.find_or_initialize_by(name: "Restaurante", is_default: true, category_type: "expense")
    restaurante.parent = comida
    restaurante.slug ||= "restaurante"
    restaurante.save!
  end

  def down
    restaurante = Category.find_by(name: "Restaurante", is_default: true, category_type: "expense")
    restaurante&.destroy!
    comida = Category.find_by(name: "Comida", is_default: true, category_type: "expense")
    comida&.update!(name: "Comida y restaurantes")
  end
end
