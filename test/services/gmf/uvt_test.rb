# frozen_string_literal: true

require "test_helper"

class GmfUvtTest < ActiveSupport::TestCase
  setup do
    GmfUvtYear.find_or_create_by!(year: 2026) { |r| r.value = 52374.00 }
  end

  test "value_for returns seeded value" do
    assert_equal BigDecimal("52374.0"), Gmf::Uvt.value_for(2026)
  end

  test "exemption_limit is 350 times uvt" do
    expected = BigDecimal("52374.0") * 350
    assert_equal expected, Gmf::Uvt.exemption_limit(2026)
  end

  test "falls back to latest year when missing" do
    assert_equal BigDecimal("52374.0"), Gmf::Uvt.value_for(2030)
  end
end
