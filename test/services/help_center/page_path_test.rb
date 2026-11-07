# frozen_string_literal: true

require "test_helper"

class HelpCenterPagePathTest < ActiveSupport::TestCase
  test "clasifica landing, categoría y artículo" do
    assert_predicate HelpCenter::PagePath.new("ayuda"), :root?
    assert_predicate HelpCenter::PagePath.new("ayuda/gastos"), :category?
    assert_predicate HelpCenter::PagePath.new("ayuda/gastos/registrar-gasto"), :article?
  end

  test "extrae la categoría de un artículo" do
    path = HelpCenter::PagePath.new("/ayuda/gastos/registrar-gasto/")

    assert_equal "ayuda/gastos/registrar-gasto", path.to_s
    assert_equal "ayuda/gastos", path.category_path
  end

  test "rechaza paths fuera de /ayuda" do
    refute_predicate HelpCenter::PagePath.new("gastos"), :valid?
    refute_predicate HelpCenter::PagePath.new("ayuda-extra/gastos"), :valid?
  end

  test "rechaza slugs mal formados" do
    %w[
      ayuda/Gastos
      ayuda/gastos/registrar_gasto
      ayuda/gastos/registrar--gasto
      ayuda/gastos/registrar/gasto
    ].each do |path|
      refute_predicate HelpCenter::PagePath.new(path), :valid?, "#{path} no debería ser válido"
    end
  end

  test "acepta guiones y números en los slugs" do
    assert_predicate HelpCenter::PagePath.new("ayuda/gastos-2026/registrar-1-gasto"), :valid?
  end

  test "identifica paths bajo /ayuda aunque no sean válidos" do
    assert_predicate HelpCenter::PagePath.new("ayuda/gastos/registrar/gasto"), :help_center?
    refute_predicate HelpCenter::PagePath.new("gastos"), :help_center?
  end
end
