require "test_helper"

class PricingPageTest < ActionDispatch::IntegrationTest
  test "pricing page renders real prices" do
    get pricing_path
    assert_response :success
    assert_match "14.900", response.body
    assert_match "149.900", response.body
  end

  test "pricing page shows dynamic trial days" do
    PaymentEngine::Setting.current.update!(free_trial_duration_days: 45)
    get pricing_path
    assert_response :success
    assert_match "45 días", response.body
  ensure
    PaymentEngine::Setting.current.update!(free_trial_duration_days: 60)
  end

  test "trial disabled hides trial card" do
    PaymentEngine::Setting.current.update!(free_trial_enabled: false)
    get pricing_path
    assert_response :success
    refute_match "Comenzar gratis", response.body
  ensure
    PaymentEngine::Setting.current.update!(free_trial_enabled: true)
  end
end