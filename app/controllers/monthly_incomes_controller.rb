# frozen_string_literal: true

class MonthlyIncomesController < ApplicationController
  include RecurringTemplateActions
  include ActionView::Helpers::NumberHelper

  # Also loaded when create/update re-render the index after a validation
  # error, because the summary strip is part of that same view.
  before_action :load_recurring_summary, only: %i[index create update]

  private

  def load_recurring_summary
    @recurring_summary = RecurringIncomes::CycleSummary.new(
      user: current_user,
      period: @current_period || current_listing_period
    ).call
  end

  def index_path
    monthly_incomes_path
  end

  def template_kind
    "income"
  end
end
