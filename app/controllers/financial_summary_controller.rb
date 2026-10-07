# frozen_string_literal: true

class FinancialSummaryController < ApplicationController
  before_action :authenticate_user!

  def show
    @cycle = Reports::Period.cycles_enabled?(current_user) ? PayCycle.current(current_user) : nil
    @summary = FinancialSummaryService.new(user: current_user, month: Time.zone.today, cycle: @cycle).call
  end
end
