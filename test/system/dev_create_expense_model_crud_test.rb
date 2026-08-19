require "application_system_test_case"

class DevCreateExpenseModelCrudTest < ApplicationSystemTestCase
  test "expense model and crud exist" do
    # Verify expense model exists
    assert defined?(Expense), "Expense model should be defined"
    
    # Verify controller exists
    assert defined?(ExpensesController), "ExpensesController should be defined"
    
    # Verify routes exist
    assert Rails.application.routes.recognize_path("/expenses", method: :get)
    assert Rails.application.routes.recognize_path("/expenses/new", method: :get)
  end
end
