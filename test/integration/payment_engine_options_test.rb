require "test_helper"

class PaymentEngineOptionsTest < ActiveSupport::TestCase
  setup do
    @mt = PaymentEngine::MembershipType.find_or_create_by!(code: "BASIC") { |m| m.name = "Membresía Básica"; m.status = "active" }
  end

  test "seed creates exactly two options" do
    # emulate seed
    PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @mt, name: "Mensual") do |po|
      po.price = 14900; po.currency = "COP"; po.mode = "recurring"; po.interval = "month"; po.interval_count = 1; po.access_duration_count = 1; po.access_duration_unit = "month"; po.status = "active"; po.position = 1
    end
    PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @mt, name: "Anual") do |po|
      po.price = 149900; po.currency = "COP"; po.mode = "one_time"; po.access_duration_count = 12; po.access_duration_unit = "month"; po.status = "active"; po.position = 2
    end
    assert_equal 2, PaymentEngine::PaymentOption.where(membership_type: @mt).count
    monthly = PaymentEngine::PaymentOption.find_by(membership_type: @mt, name: "Mensual")
    annual = PaymentEngine::PaymentOption.find_by(membership_type: @mt, name: "Anual")
    assert monthly.recurring?
    assert annual.one_time?
    assert_equal 1, monthly.access_duration_count
    assert_equal "month", monthly.access_duration_unit
    assert_equal 12, annual.access_duration_count
    assert_equal "month", annual.access_duration_unit
  end

  test "idempotent seed does not duplicate" do
    PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @mt, name: "Mensual") { |po| po.price = 14900 }
    before = PaymentEngine::PaymentOption.count
    PaymentEngine::PaymentOption.find_or_create_by!(membership_type: @mt, name: "Mensual") { |po| po.price = 14900 }
    assert_equal before, PaymentEngine::PaymentOption.count
  end

  test "access duration computes duration" do
    po = PaymentEngine::PaymentOption.new(access_duration_count: 12, access_duration_unit: "month")
    assert_equal 12.months, po.access_duration
  end
end
