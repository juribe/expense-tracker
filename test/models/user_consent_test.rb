# frozen_string_literal: true

require "test_helper"

class UserConsentTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(
      name: "Consent Model User",
      email: "consent-model-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  test "accepts only known consent types" do
    consent = @user.user_consents.new(
      consent_type: "newsletter",
      granted: true,
      occurred_at: Time.current
    )

    refute consent.valid?
    assert consent.errors[:consent_type].present?
  end

  test "requires a document version for legal consents" do
    %w[terms privacy].each do |type|
      consent = @user.user_consents.new(
        consent_type: type,
        granted: true,
        occurred_at: Time.current
      )

      refute consent.valid?
      assert consent.errors[:document_version].present?
    end
  end

  test "does not require a document version for marketing consent" do
    consent = @user.user_consents.new(
      consent_type: "marketing",
      granted: false,
      occurred_at: Time.current
    )

    assert consent.valid?
  end

  test "records terms and privacy acceptances with versions and timestamps" do
    assert_difference -> { @user.user_consents.count }, 3 do
      UserConsent.record_registration_acceptances!(@user, marketing_granted: false)
    end

    legal = @user.user_consents.legal.order(:consent_type)

    assert_equal %w[privacy terms], legal.map(&:consent_type)
    assert_equal [ "2026-11-07", "2026-11-06" ], legal.map(&:document_version)
    assert legal.all? { |consent| consent.user == @user }
    assert legal.all?(&:granted?)
    assert legal.all? { |consent| consent.occurred_at.present? }
  end

  test "records marketing state even when declined" do
    UserConsent.record_registration_acceptances!(@user, marketing_granted: false)

    marketing = @user.user_consents.marketing.first

    assert marketing.present?
    refute marketing.granted?
    assert marketing.occurred_at.present?
  end

  test "returns the latest marketing status" do
    travel_to(Time.zone.parse("2026-11-07 09:00:00")) do
      UserConsent.record_marketing_consent!(@user, granted: true)
    end

    travel_to(Time.zone.parse("2026-11-07 10:00:00")) do
      UserConsent.record_marketing_consent!(@user, granted: false)
    end

    refute UserConsent.marketing_granted?(@user)
    refute UserConsent.marketing_status(@user).granted?
  end

  test "returns false when there is no marketing consent" do
    refute UserConsent.marketing_granted?(@user)
    assert_nil UserConsent.marketing_status(@user)
  end

  test "removes consents when the user is destroyed" do
    UserConsent.record_registration_acceptances!(@user, marketing_granted: true)

    assert_difference -> { UserConsent.count }, -3 do
      @user.destroy
    end
  end
end
