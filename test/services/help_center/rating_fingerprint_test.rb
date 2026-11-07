# frozen_string_literal: true

require "test_helper"

class HelpCenterRatingFingerprintTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    @page = Struct.new(:id).new("page-1")
    @request = ActionDispatch::TestRequest.create(
      "REMOTE_ADDR" => "203.0.113.9",
      "HTTP_USER_AGENT" => "HelpCenterTest/1.0"
    )
  end

  test "los usuarios autenticados usan su identificador" do
    user = Struct.new(:id).new(42)

    fingerprint = HelpCenter::RatingFingerprint.call(page: @page, user: user, request: @request)

    assert_equal "user:42", fingerprint
  end

  test "los anónimos usan un hash sin IP en claro" do
    fingerprint = HelpCenter::RatingFingerprint.call(page: @page, user: nil, request: @request)

    assert_match(/\Aanon:[a-f0-9]{64}\z/, fingerprint)
    refute_includes fingerprint, "203.0.113.9"
  end

  test "el fingerprint anónimo cambia al día siguiente" do
    first = travel_to(Time.zone.local(2026, 11, 6, 10, 0, 0)) do
      HelpCenter::RatingFingerprint.call(page: @page, user: nil, request: @request)
    end

    second = travel_to(Time.zone.local(2026, 11, 7, 10, 0, 0)) do
      HelpCenter::RatingFingerprint.call(page: @page, user: nil, request: @request)
    end

    refute_equal first, second
  end

  test "el fingerprint anónimo cambia por artículo" do
    other_page = Struct.new(:id).new("page-2")

    first = HelpCenter::RatingFingerprint.call(page: @page, user: nil, request: @request)
    second = HelpCenter::RatingFingerprint.call(page: other_page, user: nil, request: @request)

    refute_equal first, second
  end
end
