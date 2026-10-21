# frozen_string_literal: true

require "test_helper"
require "tempfile"

class RecurringTemplateImporterTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Importer User", email: "importer_test@example.com", password: "password123")
    @expense_food = Category.create!(user: nil, name: "Comida", category_type: "expense", is_default: true)
    @expense_transport = Category.create!(user: nil, name: "Transporte", category_type: "expense", is_default: true)
    @income_salary = Category.create!(user: nil, name: "Salario", category_type: "income", is_default: true)
  end

  test "preview validates rows and never touches the database" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Comida,gasto,50000,Almuerzo,15,verdadero
      Inexistente,gasto,10000,Peluquería,3,falso
      Comida,alquiler,50000,Arriendo,10,verdadero
      Comida,gasto,,Arriendo,10,verdadero
    CSV

    assert_empty @user.recurring_templates
    assert_equal 4, rows.size

    ok = rows[0]
    assert_equal "ok", ok["status"]
    assert_equal @expense_food.id, ok["category_id"]
    assert_equal "Almuerzo", ok["description"]
    assert_equal "15", ok["payment_day"]
    assert_nil ok["error"]

    bad_category = rows[1]
    assert_equal "error", bad_category["status"]
    assert_nil bad_category["category_id"]
    assert_match(/la categoría "Inexistente" no existe/, bad_category["error"])

    bad_kind = rows[2]
    assert_equal "error", bad_kind["status"]
    assert_match(/el tipo debe ser ingreso o gasto/, bad_kind["error"])

    blank_amount = rows[3]
    assert_equal "error", blank_amount["status"]
    assert_match(/el monto es requerido/, blank_amount["error"])
  end

  test "preview statuses set the kind before category resolution" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción
      Salario,gasto,50000,Arriendo de tipo incorrecto
      Comida,gasto,50000,Uso de default cuando el tipo se omite
    CSV

    assert_match(/la categoría "Salario" no existe/, rows[0]["error"])
    assert_equal "expense", rows[1]["kind"]
    assert_equal "ok", rows[1]["status"]
  end

  test "import inserts the resolved rows inside a single transaction" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Comida,gasto,50000,Almuerzo,15,verdadero
      Salario,ingreso,1000000,Sueldo,1,falso
    CSV

    importer = RecurringTemplateImporter.new(user: @user)
    importer.import(rows)

    assert_empty importer.row_errors
    assert_equal 2, @user.recurring_templates.count

    expense = @user.recurring_templates.find_by!(description: "Almuerzo")
    assert_equal "expense", expense.kind
    assert_equal BigDecimal("50000"), expense.amount
    assert_equal @expense_food.id, expense.category_id
    assert_equal 15, expense.payment_day
    assert expense.active?

    income = @user.recurring_templates.find_by!(description: "Sueldo")
    assert_equal "income", income.kind
    assert_equal @income_salary.id, income.category_id
    refute income.active?
  end

  test "import uses the preview selection to fix a missing category" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Inexistente,gasto,10000,Peluquería,3,falso
    CSV

    importer = RecurringTemplateImporter.new(user: @user)
    importer.import(rows, category_ids: { rows.first["id"] => @expense_transport.id.to_s })

    assert_empty importer.row_errors
    template = @user.recurring_templates.first
    assert_equal @expense_transport.id, template.category_id
    assert_equal BigDecimal("10000"), template.amount
  end

  test "import keeps skipping every remaining unresolved category row" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Inexistente,gasto,10000,Peluquería,3,falso
    CSV

    importer = RecurringTemplateImporter.new(user: @user)
    importer.import(rows)

    assert_empty importer.templates
    assert_empty @user.recurring_templates
    assert_equal 1, importer.row_errors.size
    assert_match(/Fila 2: la categoría "Inexistente" no existe/, importer.row_errors.first)
  end

  test "import rejects a selection that belongs to another kind" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Inexistente,gasto,10000,Peluquería,3,falso
    CSV

    importer = RecurringTemplateImporter.new(user: @user)
    importer.import(rows, category_ids: { rows.first["id"] => @income_salary.id.to_s })

    assert_empty importer.templates
    assert_match(/la categoría "Inexistente" no existe/, importer.row_errors.first)
  end

  test "import falls back to the upload default category when the kind matches" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Inexistente,gasto,10000,Peluquería,3,falso
    CSV

    importer = RecurringTemplateImporter.new(user: @user)
    importer.import(rows, default_category_id: @expense_transport.id.to_s)

    assert_empty importer.row_errors
    template = @user.recurring_templates.first
    assert_equal @expense_transport.id, template.category_id
  end

  test "import ignores a default category of another kind" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Salario,gasto,50000,Arriendo,10,verdadero
    CSV

    importer = RecurringTemplateImporter.new(user: @user)
    importer.import(rows, default_category_id: @income_salary.id.to_s)

    assert_empty @user.recurring_templates
    assert_match(/la categoría "Salario" no existe/, importer.row_errors.first)
  end

  test "import does not match a category that exists with a different type" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Salario,gasto,50000,Arriendo,10,verdadero
    CSV

    importer = RecurringTemplateImporter.new(user: @user)
    importer.import(rows)

    assert_empty importer.templates
    assert_match(/la categoría "Salario" no existe/, importer.row_errors.first)
  end

  test "import keeps failing audibly when an unexpected error occurs" do
    rows = preview_csv(<<~CSV)
      categoría,tipo,monto,descripción,día de pago,activo
      Comida,gasto,50000,Almuerzo,15,verdadero
    CSV

    bad_row = rows.first.merge("amount" => "no numérico")
    importer = RecurringTemplateImporter.new(user: @user)
    importer.import([bad_row])

    assert_empty @user.recurring_templates
    assert_match(/Fila 2: el monto es requerido/, importer.row_errors.first)
  end

  private

  def preview_csv(content)
    file = Tempfile.new([ "plantilla", ".csv" ])
    file.write(content)
    file.rewind

    RecurringTemplateImporter.new(user: @user).preview(file)
  ensure
    file&.close!
  end
end
