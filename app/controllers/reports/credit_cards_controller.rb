# frozen_string_literal: true

# Reports::CreditCardsController
# GET /reports/credit_cards — per card usage and activity.
# Delegates all aggregation to Reports::CreditCards; keeps the controller fat-free.
class Reports::CreditCardsController < Reports::BaseController
  before_action :require_detailed_money_tracking
  def index
    @credit_cards = Reports::CreditCards.new(user: current_user, filter: report_filters).call
  end
end
