# frozen_string_literal: true

class MonthlyIncomesController < ApplicationController
  include RecurringTemplateActions
  include ActionView::Helpers::NumberHelper

  private

  def index_path
    monthly_incomes_path
  end

  def template_kind
    "income"
  end
end
