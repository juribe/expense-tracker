# frozen_string_literal: true

module Gmail
  # One-step adapter for the shared bank wizard UI. It presents the Gmail
  # identifier suggestions as a single "bank emails" step; saving goes through
  # GmailConnectionsController#update_filters and writes GmailConnection's
  # search_config, never MoneySourceRecognition.
  #
  #   Gmail::FilterWizard.new(connection: connection).steps
  class FilterWizard
    Step = Struct.new(:key, :label, :source_id, :configured, :senders, :subjects, :suggestions,
                      keyword_init: true)

    def initialize(connection:)
      @connection = connection
    end

    def steps
      [ build_step ]
    end

    private

    def build_step
      values = @connection.criteria_form_values
      Step.new(
        key: "bank_filters",
        label: I18n.t("gmail.filter_wizard.step_label", default: "Correos de bancos"),
        source_id: nil,
        configured: @connection.search_configured?,
        senders: split(values[:senders]) + split(values[:domains]),
        subjects: split(values[:subject_keywords]),
        suggestions: {
          senders: suggestion_entries("senders") + suggestion_entries("domains"),
          subjects: suggestion_entries("subject_keywords") + suggestion_entries("subject_templates")
        }
      )
    end

    def split(value)
      value.to_s.split(",").map(&:strip).reject(&:blank?).uniq
    end

    def suggestion_entries(section)
      Array(suggestions[section]).filter_map do |entry|
        value = entry.is_a?(Hash) ? (entry["value"] || entry[:value]) : entry
        value = value.to_s.strip
        next if value.blank?

        {
          value: value,
          count: entry.is_a?(Hash) ? entry["count"].to_i : 0,
          institution: entry.is_a?(Hash) ? (entry["institution"].presence || entry[:institution].presence) : nil
        }
      end
    end

    def suggestions
      @connection.setup_suggestions.is_a?(Hash) ? @connection.setup_suggestions : {}
    end
  end
end
