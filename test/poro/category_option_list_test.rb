# frozen_string_literal: true

require "test_helper"

class CategoryOptionListTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "List User", email: "option_list_#{Time.now.to_i}@example.com", password: "password123")
  end

  test "is empty for an empty collection" do
    assert_empty CategoryOptionList.new([]).options
  end

  test "keeps every category exactly once, defaults and custom alike" do
    comida = create_default("Comida")
    create_default("Transporte", parent: comida)
    create_custom("Crypto")

    options = CategoryOptionList.new(Category.all).options

    assert_equal Category.count, options.size
    assert_equal Category.pluck(:id).sort, options.map(&:id).sort
  end

  test "sorts everything alphabetically, ignoring defaults vs custom" do
    create_default("Zapatos")
    create_custom("Alquiler")
    create_default("Comida")
    create_custom("Bodega")

    options = CategoryOptionList.new(Category.all).options

    assert_equal %w[Alquiler Bodega Comida Zapatos], options.map(&:name)
  end

  test "sorts with an accent-insensitive key" do
    create_default("Árbol")
    create_default("Arroz")
    create_default("Zapatos")

    options = CategoryOptionList.new(Category.all).options

    assert_equal %w[Árbol Arroz Zapatos], options.map(&:name)
  end

  test "search_text is the category's own name, not its ancestors" do
    comida = create_default("Comida")
    restaurante = create_default("Restaurante", parent: comida)

    option = CategoryOptionList.new(Category.all).options.find { |item| item.id == restaurante.id }

    assert_equal "restaurante", option.search_text
  end

  test "accepts a relation as well as an array" do
    create_default("Comida")
    create_custom("Crypto")

    assert_equal 2, CategoryOptionList.new(Category.for_user(@user)).options.size
  end

  test "does not issue extra queries for the collection it is given" do
    create_default("Comida")
    create_custom("Crypto")
    categories = Category.for_user(@user).to_a

    queries = count_queries { CategoryOptionList.new(categories).options }

    assert_equal 0, queries
  end

  private

  def count_queries
    count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].to_s.strip.start_with?("SELECT")
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  def create_default(name, parent: nil)
    Category.create!(name: name, is_default: true, category_type: "expense", parent: parent)
  end

  def create_custom(name, parent: nil)
    Category.create!(name: name, is_default: false, category_type: "expense", user: @user, parent: parent)
  end
end
