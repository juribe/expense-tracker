# frozen_string_literal: true

require "test_helper"

class SubcategorySavingTipTest < ActiveSupport::TestCase
  setup do
    @category = Category.create!(name: "Tips Cat", is_default: true, category_type: "expense")
  end

  test "requires title and body" do
    tip = SubcategorySavingTip.new(subcategory: @category, title: "", body: "")
    assert_not tip.valid?
  end

  test "active scope filters inactive tips" do
    active = @category.saving_tips.create!(title: "A", body: "B", active: true, position: 0)
    inactive = @category.saving_tips.create!(title: "C", body: "D", active: false, position: 1)
    assert_includes SubcategorySavingTip.active, active
    assert_not_includes SubcategorySavingTip.active, inactive
  end

  test "ordered scope by position" do
    t2 = @category.saving_tips.create!(title: "Second", body: "b", active: true, position: 2)
    t1 = @category.saving_tips.create!(title: "First", body: "a", active: true, position: 1)
    assert_equal [ t1, t2 ], @category.saving_tips.ordered.to_a
  end
end
