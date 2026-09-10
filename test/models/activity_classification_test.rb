# frozen_string_literal: true

require "test_helper"

class ActivityClassificationTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Classification User", email: "clf@example.com", password: "password123")
    @food = Category.create!(name: "Comida y restaurantes", is_default: true, category_type: "expense")
    @transport = Category.create!(name: "Transporte", is_default: true, category_type: "expense")
  end

  test "normalize_name collapses case, accents and merchant reference suffixes" do
    assert_equal "didi food", ActivityClassification.normalize_name("DIDI FOOD")
    assert_equal "didi food", ActivityClassification.normalize_name("didi food")
    assert_equal "didi food", ActivityClassification.normalize_name("Didi Food")
    assert_equal "didi food", ActivityClassification.normalize_name("DIDI FOOD *12345")
    assert_equal "did food", ActivityClassification.normalize_name("Did*Food")
  end

  test "record! is idempotent per user and normalized name" do
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: @food, source: "ai")
    ActivityClassification.record!(user: @user, name: "didi FOOD", category: @transport, source: "ai")

    assert_equal 1, @user.activity_classifications.count
  end

  test "a user correction overrides an earlier AI classification" do
    ai = ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: @food, source: "ai")
    assert_equal "ai", ai.source
    assert_equal @food, ai.category

    ActivityClassification.record!(user: @user, name: "didí food", category: @transport, source: "user")

    assert_equal "user", ai.reload.source
    assert_equal @transport, ai.reload.category
  end

  test "AI or rule suggestions never overwrite a user correction" do
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: @transport, source: "user")

    ActivityClassification.record!(user: @user, name: "didi food", category: @food, source: "ai")

    stored = ActivityClassification.lookup(user: @user, name: "DIDI FOOD")
    assert_equal "user", stored.source
    assert_equal @transport, stored.category
  end

  test "lookup returns the strongest stored classification" do
    ActivityClassification.record!(user: @user, name: "DIDI FOOD", category: @food, source: "ai")

    assert_equal "ai", ActivityClassification.lookup(user: @user, name: "didi food").source
  end

  test "record! resolves a category name to the user's category" do
    classification = ActivityClassification.record!(
      user: @user, name: "DIDI FOOD", category: "Comida y restaurantes", source: "rule"
    )

    assert_equal @food, classification.category
    assert_equal "rule", classification.source
  end
end
