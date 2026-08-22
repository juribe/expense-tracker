# frozen_string_literal: true

class MonthlyExpensesController < ApplicationController
  include RecurringTemplateActions
  include ActionView::Helpers::NumberHelper

  private

  def index_path
    monthly_expenses_path
  end

  def template_kind
    "expense"
  end
end
