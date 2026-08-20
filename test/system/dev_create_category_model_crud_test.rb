require "application_system_test_case"

class DevCreateCategoryModelCrudTest < ApplicationSystemTestCase
  test "category model and crud exist" do
    assert defined?(Category), "Category model should be defined"
    assert defined?(CategoriesController), "CategoriesController should be defined"
    assert Rails.application.routes.recognize_path("/categories", method: :get)
    assert Rails.application.routes.recognize_path("/categories/new", method: :get)
  end
end
