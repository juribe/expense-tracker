# frozen_string_literal: true

class MoneySourceExtractsController < ApplicationController
  include MoneySourceShowContext

  before_action :authenticate_user!
  before_action :set_money_source

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # GET /money_sources/:id/extractos
  def show
    load_payment_context if @money_source.debt?
    load_pocket_context if @money_source.pocket?
    load_statement_context
    @active_tab = "movimientos"
    render "money_sources/show"
  end

  alias movements show
  alias statement show
  alias extracto show

  private

  def set_money_source
    @money_source = current_user.money_sources.find(params[:id])
  end

  def load_statement_context
    @statement = MoneySources::Statement.new(
      user: current_user,
      source: @money_source,
      period: params[:period],
      start_date: params[:start_date],
      end_date: params[:end_date],
      kind: params[:kind],
      query: params[:q],
      page: params[:page],
      per_page: params[:per_page]
    ).call
  end

  def not_found
    head :not_found
  end
end
