# frozen_string_literal: true

require "test_helper"

class MoneySourceGmfTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(name: "GMF User", email: "gmf_ms@example.com", password: "password123")
  end

  def create_source(**overrides)
    @user.money_sources.create!({ name: "Cuenta", kind: "account", starting_balance: 1000 }.merge(overrides))
  end

  test "account can be marked gmf_exempt" do
    source = create_source(gmf_exempt: true)
    assert source.gmf_exempt?
  end

  test "only one account per user can be gmf_exempt" do
    a = create_source(name: "A", gmf_exempt: true)
    b = create_source(name: "B")
    b.update!(gmf_exempt: true)
    assert_not a.reload.gmf_exempt?
    assert b.reload.gmf_exempt?
  end

  test "non-account kinds cannot be gmf_exempt" do
    source = MoneySource.new(user: @user, name: "Cash", kind: "cash", gmf_exempt: true)
    assert_not source.valid?
  end

  test "enable_gmf_exemption unmarks previous" do
    a = create_source(name: "A", gmf_exempt: true)
    b = create_source(name: "B")
    b.enable_gmf_exemption!
    assert_not a.reload.gmf_exempt?
    assert b.reload.gmf_exempt?
  end
end
