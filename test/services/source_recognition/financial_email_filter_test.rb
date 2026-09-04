# frozen_string_literal: true

require "test_helper"

module SourceRecognition
  class FinancialEmailFilterTest < ActiveSupport::TestCase
    setup do
      require Rails.root.join("db/seed_data/financial_catalog_seeder")
      FinancialCatalogSeeder.run
      @filter = FinancialEmailFilter.new
    end

    def email(from: "Davibank <notificaciones@davibank.com>", subject: "Transacción aprobada",
              body: "DAVIbank te notifica que realizaste con tu tarjeta Clasica una transacción de 20,300.")
      { id: "m1", from: from, subject: subject, body_text: body }
    end

    test "scores a typical transaction email very high and passes it" do
      result = @filter.call(email)

      assert result.passed?
      assert result.score >= FinancialEmailFilter::PASS_THRESHOLD
      assert_equal "DAVIbank", result.institution.canonical_name
      assert_equal "davibank", result.alias_matched
    end

    test "matches the institution by verified domain (accent-folded)" do
      result = @filter.call(email(from: "Banco Davivienda <notificaciones@mail.davivienda.com>"))

      assert result.passed?
      assert_equal "Davivienda", result.institution.canonical_name
    end

    test "matches the institution by alias in text even without a known domain" do
      result = @filter.call(
        email(from: "alertas@avisos-bancarios.net", subject: "Movimiento en tu cuenta",
              body: "Banco de Bogotá informa: transferencia recibida por 300.000.")
      )

      assert result.passed?
      assert_equal "Banco de Bogotá", result.institution.canonical_name
    end

    test "accent normalization: transacción ~ transaccion and clásica ~ clasica" do
      result = @filter.call(email(subject: "Transaccion aprobada", body: "tu tarjeta clasica fue usada"))

      assert result.passed?
      assert result.subject_patterns.any?
      assert result.body_keywords.any?
    end

    test "rejects a marketing email from a bank domain" do
      result = @filter.call(
        email(subject: "Conoce nuestra nueva tarjeta",
              body: "DAVIbank te invita a conocer los beneficios y la promoción exclusiva de nuestra nueva tarjeta de crédito.")
      )

      assert_not result.passed?
      assert_equal 0, result.score
    end

    test "a bank domain alone is not enough: no transactional signal, no pass" do
      result = @filter.call(
        email(subject: "Bienvenido a Davibank", body: "Gracias por abrir tu cuenta en DAVIbank.")
      )

      assert_not result.passed?
      assert_equal "DAVIbank", result.institution.canonical_name
      assert result.score.positive?
    end

    test "subject pattern and subject keywords are medium signals" do
      result = @filter.call(
        email(from: "avisos@unknown-domain.xyz", subject: "Transacción aprobada",
              body: "El detalle de la operación está disponible en tu app.")
      )

      assert result.passed?
      assert result.subject_patterns.any?
      assert result.subject_keywords.any?
    end

    test "security-only keywords in the body do not make an email transactional" do
      result = @filter.call(
        email(subject: "Hola", body: "Tu código de verificación de seguridad es 123456.")
      )

      assert_not result.passed?
    end

    test "non-financial personal email does not pass" do
      result = @filter.call(
        email(from: "amigo@correo.com", subject: "Feliz cumpleaños", body: "Nos vemos el sábado!")
      )

      assert_not result.passed?
      assert_equal 0, result.score
    end

    test "handles legacy message shape without from" do
      result = @filter.call({ id: "m", subject: "Transacción aprobada", body_text: "compra realizada" })

      assert result.passed?
      assert_nil result.institution
    end

    test "handles a binary (ASCII-8BIT) encoded body without raising" do
      binary_body = "DAVIbank: transacción aprobada con tu tarjeta Clasica por 120.000".dup.force_encoding(Encoding::ASCII_8BIT)
      binary_subject = "Transacción aprobada".dup.force_encoding(Encoding::ASCII_8BIT)

      result = @filter.call(email(body: binary_body, subject: binary_subject))

      assert result.passed?
    end
  end
end
