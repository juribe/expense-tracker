# frozen_string_literal: true

require "csv"

# Reports::CycleTransactionsCsv
# CSV representation of the movements already filtered for one cycle. The
# caller owns the query, so the export can never include another cycle or
# another user's records.
#
# Methods: call
#
# Example: Reports::CycleTransactionsCsv.new(records: query.call.to_a).call
class Reports::CycleTransactionsCsv
  HEADERS = [
    I18n.t("common.date"),
    I18n.t("common.type"),
    I18n.t("common.description"),
    I18n.t("common.category"),
    I18n.t("common.amount")
  ].freeze

  def initialize(records:)
    @records = records
  end

  def call
    CSV.generate do |csv|
      csv << HEADERS
      records.each { |transaction| csv << row_for(transaction) }
    end
  end

  private

  attr_reader :records

  def row_for(transaction)
    [
      transaction.date.iso8601,
      transaction.kind == "income" ? I18n.t("types.income") : I18n.t("types.expense"),
      transaction.description.to_s,
      transaction.category&.name.to_s,
      transaction.amount
    ]
  end
end
