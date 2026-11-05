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

  test "does not promise automatic renewal" do
    get pricing_path

    assert_response :success
    refute_match(/renovación automática/i, response.body)
    refute_match(/renueva automáticamente/i, response.body)
    refute_match(/autorizas la renovación/i, response.body)
  end

  test "monthly and annual faq explains payment cadence" do
    get pricing_path

    assert_response :success
    assert_match "El mensual cuesta $14.900 COP y se paga cada mes", response.body
    assert_match "El anual cuesta $149.900 COP y cubre 12 meses de uso", response.body
    refute_match "se paga por cada periodo", response.body
    refute_match "se paga una sola vez", response.body
  end

  test "payment methods faq explains option availability" do
    get pricing_path

    assert_response :success
    assert_match "¿Qué medios de pago puedo utilizar?", response.body
    assert_match "Puedes pagar tu suscripción con tarjeta de crédito, tarjeta débito o PSE", response.body
    assert_match "Todos los pagos son individuales", response.body
    refute_match "¿Puedo pagar con PSE?", response.body
  end
end
