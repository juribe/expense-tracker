# frozen_string_literal: true

# Reports::BaseController
# Shared authentication, period and filter handling for the Reports section;
# every section controller is a two-line action that delegates to a report
# service under app/services/reports/.
class Reports::BaseController < ApplicationController
  before_action :authenticate_user!
  before_action :set_report_filters

  private

  attr_reader :report_filters

  def set_report_filters
    @period = build_period
    @report_filters = Reports::Filter.new(user: current_user, period: @period, **report_filter_params)
  end

  def build_period
    Reports::Period.new(
      preset: params[:period],
      date: Date.current,
      start_date: parse_date(params[:start_date]),
      end_date: parse_date(params[:end_date])
    )
  end

  def parse_date(raw)
    Date.parse(raw) if raw.present?
  rescue Date::Error
    nil
  end

  def report_filter_params
    params.permit(:category_id, :money_source_id, :credit_card_id, :loan_id, :kind).to_h.symbolize_keys
  end
end
