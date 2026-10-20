# frozen_string_literal: true

require "test_helper"

class CategoriesClosestResolverTest < ActiveSupport::TestCase
  def setup
    @user = User.create!(name: "Resolver User",
                         email: "resolver-#{SecureRandom.hex(6)}@example.com",
                         password: "password123")
    @comida = Category.create!(name: "Comida", user: @user, is_default: false)
    @restaurante = Category.create!(name: "Restaurante", parent: @comida, user: @user, is_default: false)
    @hogar = Category.create!(name: "Hogar", user: @user, is_default: false)
    @servicios = Category.create!(name: "Servicios públicos", user: @user, is_default: false)
    @otras = Category.create!(name: "Otros", user: @user, is_default: false)
    @entretenimiento = Category.create!(name: "Entretenimiento", user: @user, is_default: false)
    @transporte = Category.create!(name: "Transporte", user: @user, is_default: false)
  end

  def resolve(name, activity: nil, record: false)
    Categories::ClosestResolver.call(user: @user, name: name, activity: activity, record: record)
  end

  test "matches an existing category by exact normalized name" do
    result = resolve("COMIDA")

    assert_equal @comida, result.category
    assert_equal :exact, result.matched_by
  end

  test "matches a subcategory by exact normalized name" do
    result = resolve("Restaurante")

    assert_equal @restaurante, result.category
    assert_equal :exact, result.matched_by
  end

  test "folds English seed names into the Restaurante subcategory when it exists" do
    result = resolve("Restaurants")

    assert_equal @restaurante, result.category
    assert_equal :alias, result.matched_by
  end

  test "folds the legacy 'Comida y restaurantes' label into the Comida parent" do
    result = resolve("Comida y restaurantes")

    assert_equal @comida, result.category
    assert_equal :alias, result.matched_by
  end

  test "folds groceries into the current Mercado category" do
    mercado = Category.create!(name: "Mercado", user: @user, is_default: false)
    result = resolve("groceries")

    assert_equal mercado, result.category
    assert_equal :alias, result.matched_by
  end

  test "folds shopping into the current Gustos y compras category" do
    gustos = Category.create!(name: "Gustos y compras", user: @user, is_default: false)
    result = resolve("shopping")

    assert_equal gustos, result.category
    assert_equal :alias, result.matched_by
  end

  test "folds utilities into the current Servicios y comunicaciones category" do
    servicios = Category.create!(name: "Servicios y comunicaciones", user: @user, is_default: false)
    result = resolve("utilities")

    assert_equal servicios, result.category
    assert_equal :alias, result.matched_by
  end

  test "folds entertainment into the current Ocio y salidas category" do
    ocio = Category.create!(name: "Ocio y salidas", user: @user, is_default: false)
    result = resolve("entertainment")

    assert_equal ocio, result.category
    assert_equal :alias, result.matched_by
  end

  test "folds restaurants into the current Restaurantes y cafés category" do
    restaurantes = Category.create!(name: "Restaurantes y cafés", user: @user, is_default: false)
    result = resolve("restaurants")

    assert_equal restaurantes, result.category
    assert_equal :alias, result.matched_by
  end

  test "folds market into the current Mercado category" do
    mercado = Category.create!(name: "Mercado", user: @user, is_default: false)
    result = resolve("market")

    assert_equal mercado, result.category
    assert_equal :alias, result.matched_by
  end

  test "folds clothing into the current Gustos y compras category" do
    gustos = Category.create!(name: "Gustos y compras", user: @user, is_default: false)
    result = resolve("clothing")

    assert_equal gustos, result.category
    assert_equal :alias, result.matched_by
  end

  test "prefers the current category when both current and legacy targets exist" do
    mercado = Category.create!(name: "Mercado", user: @user, is_default: false)
    Category.create!(name: "Compras", user: @user, is_default: false)

    assert_equal mercado, resolve("groceries").category
  end

  test "keeps legacy alias targets as fallback" do
    compras = Category.create!(name: "Compras", user: @user, is_default: false)

    assert_equal compras, resolve("groceries").category
    assert_equal compras, resolve("shopping").category
    assert_equal @servicios, resolve("utilities").category
    assert_equal @entretenimiento, resolve("entertainment").category
  end

  test "folds near-identical labels by token similarity without creating categories" do
    assert_no_difference "Category.count" do
      result = resolve("Restaurante (Rappi)")
      assert_equal @restaurante, result.category
      assert_equal :similar, result.matched_by
    end
  end

  test "folds near-duplicate names by token similarity without creating categories" do
    assert_no_difference "Category.count" do
      result = resolve("Comida rappi")
      assert_equal @comida, result.category
      assert_equal :similar, result.matched_by
    end
  end

  test "a genuinely-new name resolves to nil instead of creating a category" do
    assert_no_difference "Category.count" do
      result = resolve("Suscripciones Digitales")
      assert_nil result.category
      assert_not result.matched?
    end
  end

  test "folds Spanish health synonyms into Salud when the category exists" do
    salud = Category.create!(name: "Salud", user: @user, is_default: false)

    assert_equal salud, resolve("Medicinas", activity: "compré unas medicinas").category
    assert_equal salud, resolve("medicina").category
    assert_equal salud, resolve("Medicamentos").category
    assert_equal salud, resolve("farmacia").category
    assert_equal salud, resolve("Drogueria").category
  end

  test "health synonyms stay unmatched when the user lacks the Salud category" do
    result = resolve("Medicinas")

    assert_not result.matched?
  end

  test "learned classifications win over similarity for the same activity" do
    entertainment = Category.create!(name: "Entretenimiento", user: @user, is_default: false)
    ActivityClassification.record!(user: @user, name: "Pago de Netflix", category: entertainment, source: "user")

    result = resolve("Rappi", activity: "Pago de Netflix")

    assert_equal entertainment, result.category
    assert_equal :learned, result.matched_by
  end

  test "record: true persists similarity folds as rule knowledge" do
    resolve("Comida restaurante", activity: "Pedimos por Rappi hoy", record: true)

    learned = ActivityClassification.lookup(user: @user, name: "Pedimos por Rappi hoy")
    assert_equal @restaurante.id, learned.category_id
    assert_equal "rule", learned.source
  end

  test "record: false never persists similarity folds" do
    assert_no_difference "ActivityClassification.count" do
      resolve("Comida restaurante", activity: "Pedimos por Rappi hoy", record: false)
    end
  end

  test "no unconditional brand rules: a generic existing category wins over the activity" do
    result = resolve("Servicios públicos", activity: "Netflix")

    assert_equal @servicios, result.category
    assert_equal :exact, result.matched_by
  end

  test "an explicit user mapping wins over the extracted category name for the same activity" do
    ActivityClassification.record!(user: @user, name: "Netflix", category: @comida, source: "user")

    result = resolve("Servicios públicos", activity: "Netflix")

    assert_equal @comida, result.category
    assert_equal :learned, result.matched_by
  end

  test "house maintenance/upkeep classifies as Hogar even when the name suggests a utility" do
    result = resolve("Servicios públicos", activity: "Mantenimiento del apartamento")

    assert_equal @hogar, result.category
    assert_equal :housing, result.matched_by
  end

  test "parking in the activity classifies as Transporte" do
    assert_equal @transporte, resolve("", activity: "gasté 5 mil en parqueadero").category
    assert_equal @transporte, resolve("", activity: "parqueo").category
    assert_equal @transporte, resolve("", activity: "estacionamiento").category
    assert_equal @transporte, resolve("", activity: "parking").category
  end

  test "parking aliases fold into Transporte when the name is a parking variant" do
    assert_equal @transporte, resolve("Parqueadero").category
    assert_equal @transporte, resolve("estacionamiento").category
  end

  test "parking terms never classify as Hogar even when a house place word appears" do
    result = resolve("", activity: "parqueadero del edificio")

    assert_equal @transporte, result.category
    assert_equal :parking, result.matched_by
  end

  test "rent and condominium fees classify as Hogar" do
    result = resolve("", activity: "arriendo del apartamento")
    assert_equal @hogar, result.category
    assert_equal :housing, result.matched_by

    result = resolve("", activity: "cuota de administración del edificio")
    assert_equal @hogar, result.category
    assert_equal :housing, result.matched_by
  end

  test "blank names with unknown activity stay unassigned (no unconditional fallback)" do
    result = resolve("", activity: "Canva Pro")

    assert_not result.matched?
    assert_nil result.matched_by
  end

  test "utilities never classify as Hogar even when a house place word is present" do
    result = resolve("Servicios públicos", activity: "internet del apartamento")

    assert_equal @servicios, result.category
    assert_equal :exact, result.matched_by

    result = resolve("Servicios públicos", activity: "pagué la luz de la casa")
    assert_equal @servicios, result.category
    assert_equal :exact, result.matched_by
  end

  test "household purchases (appliances/furniture) do not classify as Hogar" do
    result = resolve("", activity: "compré un electrodoméstico")

    assert_not result.matched?
    assert_nil result.matched_by
  end

  test "blank names resolve through the user's stored knowledge when available" do
    ActivityClassification.record!(user: @user, name: "Canva Pro", category: @entretenimiento, source: "user")

    result = resolve("", activity: "Canva Pro")

    assert_equal @entretenimiento, result.category
    assert_equal :learned, result.matched_by
  end

  test "blank names without activity resolve to nothing" do
    result = resolve("  ")

    assert_not result.matched?
    assert_nil result.matched_by
  end
end
