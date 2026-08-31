# frozen_string_literal: true

require "test_helper"

class FinancialSetupTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "Test User", email: "financial_setup_test@example.com", password: "password123")
  end

  def create_setup(**overrides)
    @user.financial_setups.create!({ status: "in_progress" }.merge(overrides))
  end

  test "defaults to in_progress at step zero" do
    setup = create_setup
    assert_equal "in_progress", setup.status
    assert_equal 0, setup.current_step
    assert_equal({}, setup.data)
  end

  test "records a per-step choice" do
    setup = create_setup
    setup.set_choice("credit_cards", "import")
    setup.save!
    assert_equal "import", setup.choice_for("credit_cards")
  end

  test "returns nil for an unrecorded choice" do
    setup = create_setup
    assert_nil setup.choice_for("accounts")
  end

  test "stores and replaces draft source rows" do
    setup = create_setup
    setup.replace_draft_sources("accounts", [ { "name" => "Savings" } ])
    setup.save!
    assert_equal [ { "name" => "Savings" } ], setup.draft_sources("accounts")

    setup.replace_draft_sources("accounts", [])
    setup.save!
    assert_equal [], setup.draft_sources("accounts")
  end

  test "stores import review state" do
    setup = create_setup
    setup.set_import_state("loans", { "sources" => [ { "name" => "Car Loan" } ], "duplicates" => {} })
    setup.save!
    state = setup.import_state("loans")
    assert_equal "Car Loan", state["sources"].first["name"]
  end

  test "tracks completed step count from recorded data" do
    setup = create_setup
    assert_equal 0, setup.step_count
    setup.set_choice("accounts", "skip")
    setup.save!
    assert_equal 1, setup.step_count
  end

  test "completion marks status and resets current step" do
    setup = create_setup(current_step: 3)
    setup.complete!
    assert setup.completed?
    assert_equal (-1), setup.current_step
  end

  test "dismissal keeps recorded progress" do
    setup = create_setup
    setup.set_choice("accounts", "manual")
    setup.replace_draft_sources("accounts", [ { "name" => "Savings" } ])
    setup.save!
    setup.dismiss!
    assert setup.dismissed?
    assert_equal [ { "name" => "Savings" } ], setup.draft_sources("accounts")
  end

  test "is resumable once a step is recorded or past the first step" do
    assert_not create_setup.resumable?

    setup = create_setup
    setup.set_choice("accounts", "skip")
    setup.save!
    assert setup.resumable?

    setup = create_setup(current_step: 1)
    assert setup.resumable?
  end

  test "validates status and current_step" do
    setup = create_setup
    setup.status = "bogus"
    assert_not setup.valid?
    assert_includes setup.errors[:status], I18n.t("errors.messages.inclusion")

    setup = create_setup
    setup.current_step = -2
    assert_not setup.valid?
  end
end
