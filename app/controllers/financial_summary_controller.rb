# frozen_string_literal: true

class FinancialSummaryController < ApplicationController
  before_action :authenticate_user!

  def show
    @summary = FinancialSummaryService.new(user: current_user, month: Time.zone.today).call
  end
end
