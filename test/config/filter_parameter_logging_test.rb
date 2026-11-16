# frozen_string_literal: true

require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  test "financial fields are filtered from request logs" do
    filters = Rails.application.config.filter_parameters.map(&:to_s)

    assert filters.any? { |filter| filter.include?("description") }
    assert filters.any? { |filter| filter.include?("amount") }
    assert filters.any? { |filter| filter.include?("content") }
  end

  test "bank, identity and uploaded content fields are filtered from request logs" do
    filters = Rails.application.config.filter_parameters.map(&:to_s)

    %w[phone account card iban raw_body payload headers file].each do |field|
      assert filters.any? { |filter| filter.include?(field) }, "expected #{field} to be filtered"
    end
  end
end
