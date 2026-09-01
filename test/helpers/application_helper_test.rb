# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "available_credit_for subtracts debt from the credit limit" do
    assert_equal 9000000, available_credit_for({ "credit_limit" => "10000000", "balance" => "1000000" })
  end

  test "available_credit_for floors at zero" do
    assert_equal 0, available_credit_for({ "credit_limit" => "500000", "balance" => "2000000" })
  end

  test "available_credit_for returns zero without a credit limit" do
    assert_equal 0, available_credit_for({ "balance" => "100000" })
  end

  test "money_field_value renders Colombian number format" do
    assert_equal "67.429.112,92", money_field_value(67429112.92)
    assert_equal "5.734.980", money_field_value("5734980")
    assert_equal "", money_field_value(nil)
  end
end
