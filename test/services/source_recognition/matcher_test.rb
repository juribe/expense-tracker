# frozen_string_literal: true

require "test_helper"

module SourceRecognition
  class MatcherTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Matcher User", email: "matcher_test@example.com", password: "password123")
      @clasica = create_configured_source(
        name: "Davibank Clásica", identifier: "5678",
        keywords: [ "davibank", "clasica", "5678" ], senders: [ "notificaciones@davibank.com" ]
      )
    end

    def create_configured_source(name:, keywords: [], senders: [], domains: [], subjects: [], headers: [], **opts)
      source = @user.money_sources.create!(
        { name: name, kind: "account", starting_balance: 0, bank: "davibank" }.merge(opts)
      )
      source.ensure_recognition.replace_identifiers(
        keyword: keywords, sender: senders, domain: domains, subject: subjects, header: headers
      )
      source
    end

    def email_message(from: "Davibank <notificaciones@davibank.com>", subject: "Tu compra fue aprobada",
                body: "Apreciado(a) Cliente:\n\nDAVIbank te notifica que realizaste con tu tarjeta Clasica una transacción de 20,300.",
                headers: nil)
      headers ||= [
        { "name" => "From", "value" => from },
        { "name" => "X-Banco", "value" => "Davibank" }
      ]
      { id: "msg-1", from: from, subject: subject, body_text: body, headers: headers }
    end

    def match(**opts)
      SourceRecognition::Matcher.call(user: @user, message: email_message(**opts))
    end

    test "matches by sender address case-insensitively" do
      assert_equal @clasica, match(from: "Notificaciones@Davibank.com <bounce@thirdparty.co>")
    end

    test "matches by sender display name when the sender value has no @" do
      nequi = create_configured_source(name: "Nequi", bank: "nequi", senders: [ "Davibank Notificaciones" ])
      result = match(from: "Davibank Notificaciones <bounce@thirdparty.co>", body: "movimiento registrado")
      assert_equal nequi, result
    end

    test "matches by domain with subdomains" do
      oro = create_configured_source(name: "Davibank Oro", domains: [ "DAVIBANK.COM" ], keywords: [])
      result = match(from: "no-reply@mail.davibank.com", subject: "s", body: "hola")
      assert_equal oro, result
    end

    test "matches subject case-insensitively" do
      oro = create_configured_source(name: "Davibank Oro", subjects: [ "compra aprobada" ], keywords: [])
      result = match(from: "x@otro.com", subject: "TU COMPRA APROBADA en Davibank", body: "movimiento registrado")
      assert_equal oro, result
    end

    test "matches keyword in body with accent folding (clasica ~ Clásica)" do
      assert_equal @clasica, match
    end

    test "keyword does not match inside another word" do
      otro = @user.money_sources.create!(name: "Otro Banco", kind: "account", starting_balance: 0, bank: "otro")
      otro.ensure_recognition.replace_identifiers(keyword: [ "bon" ])
      result = match(from: "otro@otro.com", subject: "s", body: "Comercio MR BONO CAFE",
                     headers: [ { "name" => "From", "value" => "otro@otro.com" } ])
      assert_nil result
    end

    test "matches RFC header pattern" do
      oro = create_configured_source(name: "Davibank Oro", headers: [ "X-Banco: davibank" ], keywords: [])
      result = match(from: "x@otro.com", subject: "s", body: "movimiento registrado")
      assert_equal oro, result
    end

    test "last four keyword matches masked tail" do
      result = match(body: "compra con su tarjeta •••• 5678 por 20,300")
      assert_equal @clasica, result
    end

    test "last four keyword matches tail of a long digit run" do
      result = match(body: "tarjeta 47512300005678 usada hoy")
      assert_equal @clasica, result
    end

    test "last four keyword matches termination phrase" do
      result = match(body: "tarjeta terminada en 5678")
      assert_equal @clasica, result
    end

    test "last four keyword does not match a bare amount" do
      result = match(from: "x@otro.com", subject: "s", body: "Monto 5,678 en el comercio")
      assert_nil result
    end

    test "last four keyword does not match when not anchored" do
      result = match(from: "x@otro.com", subject: "s", body: "codigo 5678 de verificacion")
      assert_nil result
    end

    test "last four does not match when the digit run does not end with it" do
      result = match(from: "x@otro.com", subject: "s", body: "ref 56789012 confirmada")
      assert_nil result
    end

    test "returns nil when no source is recognition-configured" do
      @clasica.recognition.destroy
      assert_nil match
    end

    test "returns nil when nothing matches" do
      assert_nil match(from: "alguien@otro.com", subject: "sin señales", body: "nada relevante aquí")
    end

    test "tied top score returns all candidates (ambiguous)" do
      oro = create_configured_source(name: "Davibank Oro", domains: [ "davibank.com" ], keywords: [])
      # Both match the sender/domain space with the same weight (3 each).
      result = match(body: "movimiento registrado", subject: "resumen")
      assert_kind_of Array, result
      assert_equal [ @clasica.id, oro.id ].sort, result.map(&:id).sort
    end

    test "strictly higher score wins among several candidates" do
      create_configured_source(name: "Davibank Oro", domains: [ "davibank.com" ], keywords: [])
      # Clásica: sender (3) + davibank keyword (1) + clasica keyword (1) = 5; Oro: domain (3).
      assert_equal @clasica, match
    end

    test "handles legacy message shape without from or headers" do
      assert_nil SourceRecognition::Matcher.call(user: @user, message: { id: "m", subject: "s", body_text: "nada" })
    end
  end
end
