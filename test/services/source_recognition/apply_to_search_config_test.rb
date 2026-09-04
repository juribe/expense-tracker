# frozen_string_literal: true

require "test_helper"

module SourceRecognition
  class ApplyToSearchConfigTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Feedback User", email: "feedback_test@example.com", password: "password123")
      @connection = GmailConnection.create!(user: @user, email: "me@gmail.com")
      @source = @user.money_sources.create!(name: "Davibank Clásica", kind: "account",
                                            starting_balance: 0, bank: "Davibank", identifier: "5678")
    end

    def config = @connection.reload.search_config_hash

    test "returns false when the user has no gmail connection" do
      other = User.create!(name: "No Gmail", email: "no_gmail@example.com", password: "password123")
      other.money_sources.create!(name: "Davibank", kind: "account", starting_balance: 0, bank: "Davibank")

      result = ApplyToSearchConfig.call(user: other)

      assert_equal false, result
    end

    test "feeds confirmed senders, domains and subject keywords into search config" do
      @source.ensure_recognition.replace_identifiers(
        sender: [ "notificaciones@davibank.com" ],
        domain: [ "davibank.com" ],
        subject: [ "Transacción aprobada" ],
        keyword: [ "davibank" ]
      )

      assert ApplyToSearchConfig.call(user: @user)

      assert_includes config[:senders], "notificaciones@davibank.com"
      assert_includes config[:domains], "davibank.com"
      assert_includes config[:subject_keywords], "Transacción aprobada"
      assert_includes config[:subject_keywords], "davibank"
    end

    test "suggested values never leak into the search config" do
      # Simulate a discovery suggestion (never confirmed).
      recognition = @source.ensure_recognition
      recognition.save!
      recognition.recognition_identifiers.create!(
        kind: "sender", value: "notificaciones@davibank.com",
        status: "suggested", origin: "gmail"
      )

      ApplyToSearchConfig.call(user: @user)

      assert_empty config[:senders]
      assert_empty config[:domains]
    end

    test "preserves pre-existing search config when merging" do
      @connection.update!(search_config: { senders: [ "old@bank.com" ], lookback_days: 30 })
      @source.ensure_recognition.replace_identifiers(domain: [ "davibank.com" ])

      ApplyToSearchConfig.call(user: @user)

      stored = @connection.reload.search_config
      assert_includes config[:senders], "old@bank.com"
      assert_includes config[:domains], "davibank.com"
      assert_equal 30, stored["lookback_days"] || stored[:lookback_days]
    end

    test "aggregates confirmed values across all of the user's sources" do
      second = @user.money_sources.create!(name: "Davibank Oro", kind: "account",
                                           starting_balance: 0, bank: "Davibank")
      @source.ensure_recognition.replace_identifiers(domain: [ "davibank.com" ])
      second.ensure_recognition.replace_identifiers(domain: [ "mail.davivienda.com" ])

      ApplyToSearchConfig.call(user: @user)

      assert_includes config[:domains], "davibank.com"
      assert_includes config[:domains], "mail.davivienda.com"
    end
  end
end
