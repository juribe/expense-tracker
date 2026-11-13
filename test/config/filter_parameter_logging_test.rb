# frozen_string_literal: true

require "test_helper"

class FilterParameterLoggingTest < ActiveSupport::TestCase
  test "financial fields are filtered from request logs" do
    filters = Rails.application.config.filter_parameters.map(&:to_s)

    assert filters.any? { |filter| filter.include?("description") }
    assert filters.any? { |filter| filter.include?("amount") }
    assert filters.any? { |filter| filter.include?("content") }
  end
end
