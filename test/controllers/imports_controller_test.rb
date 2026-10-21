# frozen_string_literal: true

require "test_helper"

class ImportsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(name: "Imports User", email: "imports_test@example.com", password: "password123")
    sign_in @user
    @expense_food = Category.create!(user: nil, name: "Comida", category_type: "expense", is_default: true)
    @expense_transport = Category.create!(user: nil, name: "Transporte", category_type: "expense", is_default: true)
    # The test cache store is null_store; the draft lives in it, so stub a
    # real store for these tests (production uses Solid Cache).
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Rails.cache = @original_cache
  end

  test "new shows the CSV template in Spanish" do
    get new_import_path

    assert_response :success
    assert_includes response.body, "categoría,tipo,monto,descripción,día de pago,activo"
    assert_includes response.body, "ingreso/gasto"
    assert_includes response.body, "verdadero/falso"
    assert_not_includes response.body, "category,kind,amount,description,payment_day,active"
  end

  test "upload redirects to the preview with the draft parsed" do
    upload_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Comida,gasto,50000,Almuerzo,15,verdadero
      Inexistente,gasto,10000,Peluquería,3,falso
    CSV

    assert_redirected_to import_preview_path

    get import_preview_path
    assert_response :success
    assert_select "[data-testid='preview-row']", 2
    assert_includes response.body, "Almuerzo"
    assert_includes response.body, "Peluquería"
    # The missing-category row offers a dropdown to pick an existing one.
    assert_select "select[data-testid='preview-category-select']", 2
    assert_select "select option[value='#{@expense_transport.id}']", 2 # both rows offer Transporte
  end

  test "preview without a draft asks for a file" do
    get import_preview_path

    assert_redirected_to new_import_path
  end

  test "confirm imports the resolved rows and clears the draft" do
    upload_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago
      Comida,gasto,50000,Almuerzo,15
      Inexistente,gasto,10000,Peluquería,3
    CSV

    post imports_path, params: { category_ids: { "r3" => @expense_transport.id.to_s } }

    assert_redirected_to monthly_expenses_path
    assert_includes flash[:notice], "2 plantillas recurrentes"
    assert_equal 2, @user.recurring_templates.count
    assert_equal @expense_transport.id, @user.recurring_templates.find_by!(description: "Peluquería").category_id

    # The draft is consumed: hitting confirm again asks for a file again.
    post imports_path
    assert_redirected_to new_import_path
    assert_equal 2, @user.recurring_templates.count
  end

  test "confirm reports skipped rows for remaining unresolved categories" do
    upload_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago
      Inexistente,gasto,10000,Peluquería,3
    CSV

    post imports_path

    assert_redirected_to new_import_path
    assert_includes flash[:alert], "la categoría \"Inexistente\" no existe"
    assert_empty @user.recurring_templates
  end

  private

  def upload_csv(content)
    file = Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: "plantillas.csv")
    post import_upload_path, params: { file: file }
  end
end
