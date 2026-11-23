# frozen_string_literal: true

require "test_helper"

module Gmail
  class FilterWizardTest < ActiveSupport::TestCase
    setup do
      @user = User.create!(name: "Filter Wizard", email: "filter_wizard_#{SecureRandom.hex(4)}@example.com",
                           password: "password123")
      @connection = GmailConnection.create!(
        user: @user,
        email: "filter-wizard@example.com",
        setup_suggestions: {
          "senders" => [ { "value" => "notifications@bank.com", "count" => 3 } ],
          "domains" => [ { "value" => "bank.com", "count" => 4 } ],
          "subject_keywords" => [ { "value" => "compra", "count" => 2 } ],
          "subject_templates" => [ { "value" => "Pago aprobado", "count" => 2 } ]
        }
      )
    end

    test "builds one review step from the Gmail suggestions" do
      step = FilterWizard.new(connection: @connection).steps.first

      assert_equal "bank_filters", step.key
      assert_equal "Correos de bancos", step.label
      assert_nil step.source_id
      refute step.configured
      assert_equal [ "notifications@bank.com", "bank.com" ], step.senders
      assert_equal [ "compra", "Pago aprobado" ], step.subjects
      assert_equal "notifications@bank.com", step.suggestions[:senders].first[:value]
      assert_equal "Pago aprobado", step.suggestions[:subjects].last[:value]
    end

    test "uses saved criteria as confirmed values" do
      @connection.update!(
        search_config: { senders: [ "saved@bank.com" ], domains: [ "savedbank.com" ],
                         subject_keywords: [ "débito" ] },
        setup_suggestions: nil,
        last_synced_at: Time.current
      )

      step = FilterWizard.new(connection: @connection).steps.first

      assert step.configured
      assert_equal [ "saved@bank.com", "savedbank.com" ], step.senders
      assert_equal [ "débito" ], step.subjects
    end
  end
end
