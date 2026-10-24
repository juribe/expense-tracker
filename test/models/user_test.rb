# frozen_string_literal: true

require "test_helper"

class UserTest < ActiveSupport::TestCase
  # Form labels for User fields render through human_attribute_name; without
  # es translations they fall back to English ("Name", "Current password").
  test "user attribute labels are translated to Spanish" do
    assert_equal "Nombre completo", User.human_attribute_name(:name)
    assert_equal "Correo electrónico", User.human_attribute_name(:email)
    assert_equal "Contraseña", User.human_attribute_name(:password)
    assert_equal "Confirmar contraseña", User.human_attribute_name(:password_confirmation)
    assert_equal "Contraseña actual", User.human_attribute_name(:current_password)
    assert_equal "Día de inicio del ciclo financiero", User.human_attribute_name(:financial_cycle_start_day)
    assert_equal "Porcentaje objetivo de capacidad de deuda", User.human_attribute_name(:debt_capacity_target_percentage)
    assert_equal "Porcentaje de alerta de capacidad de deuda", User.human_attribute_name(:debt_capacity_alert_percentage)
  end
end
