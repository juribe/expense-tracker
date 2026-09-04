# frozen_string_literal: true

require "test_helper"

module SourceRecognition
  class DiscoveryServiceTest < ActiveSupport::TestCase
    setup do
      require Rails.root.join("db/seed_data/financial_catalog_seeder")
      FinancialCatalogSeeder.run

      @user = User.create!(name: "Discovery User", email: "discovery_test@example.com", password: "password123")
      @clasica = @user.money_sources.create!(name: "Davibank Clásica", kind: "account",
                                             starting_balance: 0, bank: "Davibank", identifier: "5678")
      @oro = @user.money_sources.create!(name: "Davibank Oro", kind: "account",
                                         starting_balance: 0, bank: "Davibank")
      @service = DiscoveryService.new(@user)
    end

    def davibank_email(subject: "Transacción aprobada", from: "Davibank <notificaciones@davibank.com>",
                       body: "DAVIbank te notifica que realizaste con tu tarjeta Clasica " \
                             "una transacción de 20,300 con la tarjeta terminada en 5678.")
      { id: "m1", from: from, subject: subject, body_text: body }
    end

    def suggested(source, kind)
      source.recognition_identifiers.where(kind: kind, status: "suggested")
    end

    def values_of(identifiers)
      identifiers.map(&:value).sort
    end

    test "first sync suggests sender, domain, subject and keywords as suggestions" do
      result = @service.process(davibank_email)

      assert result.passed?
      assert_equal "DAVIbank", result.institution.canonical_name
      assert result.suggestions_created.positive?
      assert_equal [ @clasica.id, @oro.id ].sort, result.candidate_source_ids.sort

      [ @clasica, @oro ].each do |source|
        source.reload
        # Nothing is confirmed silently.
        assert_not source.recognition_configured?
        assert_equal %w[notificaciones@davibank.com], values_of(suggested(source, "sender"))
        assert_equal %w[davibank.com], values_of(suggested(source, "domain"))
        assert_equal [ "Transacción aprobada" ], values_of(suggested(source, "subject"))
        assert_includes values_of(suggested(source, "keyword")), "davibank"

        created = suggested(source, "keyword")
        assert created.all? { |id| id.origin == "gmail" }
      end
    end

    test "product keywords are never copied between same-institution sources" do
      @service.process(davibank_email)

      assert_includes values_of(suggested(@clasica, "keyword")), "clasica"
      assert_includes values_of(suggested(@clasica, "keyword")), "5678"
      assert_not_includes values_of(suggested(@oro, "keyword")), "clasica"
      assert_not_includes values_of(suggested(@oro, "keyword")), "5678"
    end

    test "institution alone does not identify the source when confirmed rules match one" do
      @clasica.ensure_recognition.replace_identifiers(keyword: [ "davibank", "clasica" ])

      result = @service.process(davibank_email)

      assert_equal [ @clasica.id ], result.candidate_source_ids
      assert_empty suggested(@oro, "sender")
      assert_empty suggested(@oro, "keyword")
      # Already-confirmed values are never re-suggested; the observed last
      # four (5678) is a NEW useful signal and lands as a suggestion.
      keywords = values_of(suggested(@clasica, "keyword"))
      assert_not_includes keywords, "davibank"
      assert_not_includes keywords, "clasica"
      assert_includes keywords, "5678"
    end

    test "confirmed values are never overwritten and never duplicated" do
      @clasica.ensure_recognition.replace_identifiers(sender: [ "notificaciones@davibank.com" ])

      @service.process(davibank_email)

      sender = @clasica.recognition_identifiers.find_by(kind: "sender", value: "notificaciones@davibank.com")
      assert sender.confirmed?
      assert_equal "user", sender.origin
      # The confirmed rule matched the email, so only Clásica is a candidate:
      # no suggestions leak to the sibling source.
      assert_empty suggested(@clasica, "sender")
      assert_empty suggested(@oro, "sender")
      assert_empty suggested(@oro, "keyword")
    end

    test "continuous sync is incremental: recurring values gain observations, no duplicates" do
      first = @service.process(davibank_email)
      created_first = first.suggestions_created
      assert created_first.positive?

      second = @service.process(davibank_email)

      assert_equal 0, second.suggestions_created
      identifier = @clasica.recognition_identifiers.find_by(kind: "sender", value: "notificaciones@davibank.com")
      assert_equal 2, identifier.observation_count
      assert_not_nil identifier.last_seen_at
      assert_equal created_first,
                   @user.money_sources.sum { |s| s.recognition_identifiers.count }
    end

    test "subject is only suggested when it contains the institution alias or a subject pattern" do
      @service.process(davibank_email(subject: "Hola", body: "DAVIbank: transacción de 20,300 con tu tarjeta Clasica"))

      assert_empty suggested(@clasica, "subject")
      assert suggested(@clasica, "keyword").any?
    end

    test "reply prefixes are stripped from suggested subjects" do
      @service.process(davibank_email(subject: "Re: Transacción aprobada"))

      assert_equal [ "Transacción aprobada" ], values_of(suggested(@clasica, "subject"))
    end

    test "marketing emails are not analyzed" do
      result = @service.process(
        davibank_email(subject: "Conoce nuestra nueva tarjeta",
                       body: "DAVIbank promoción exclusiva: descuento en tu nueva tarjeta de crédito.")
      )

      assert_not result.passed?
      assert_equal 0, result.suggestions_created
      assert_empty @clasica.recognition_identifiers
    end

    test "no money sources means no discovery" do
      @user.money_sources.destroy_all

      result = DiscoveryService.new(@user).process(davibank_email)

      assert_not result.passed?
      assert_equal 0, result.suggestions_created
    end

    test "emails from unknown institutions without matches discover nothing" do
      result = @service.process(
        davibank_email(from: "Alguien <friend@example.com>", subject: "Transacción aprobada",
                       body: "compra realizada por 20.000")
      )

      assert_equal 0, result.suggestions_created
      assert_empty @clasica.recognition_identifiers
    end

    test "does not exceed the per-kind cap" do
      @clasica.ensure_recognition.replace_identifiers(
        sender: (1..DiscoveryService::MAX_PER_KIND).map { |i| "sender#{i}@davibank.com" }
      )

      @service.process(davibank_email)

      assert_empty suggested(@clasica, "sender")
    end

    test "matcher never matches on suggested values only" do
      @service.process(davibank_email)

      matched = Matcher.call(user: @user, message: davibank_email)
      assert_nil matched
    end
  end
end
