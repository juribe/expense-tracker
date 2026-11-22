# frozen_string_literal: true

class MoneySourceExtractsController < ApplicationController
  include MoneySourceShowContext

  before_action :authenticate_user!
  before_action :require_detailed_money_tracking
  before_action :set_money_source

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # GET /money_sources/:id/extractos
  #
  # HTML renders the movements tab; CSV, XLSX and PDF download the same
  # filtered statement. The exports drop pagination so the file always covers
  # every movement matching the current period/filter.
  def show
    respond_to do |format|
      format.html do
        load_payment_context if @money_source.debt?
        load_pocket_context if @money_source.pocket?
        load_statement_context
        @active_tab = "movimientos"
        render "money_sources/show"
      end
      format.csv do
        send_statement_export(MoneySources::StatementExports::Csv, "text/csv")
      end
      format.xlsx do
        send_statement_export(
          MoneySources::StatementExports::Xlsx,
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        )
      end
      format.pdf do
        send_statement_export(MoneySources::StatementExports::Pdf, "application/pdf")
      end
    end
  end

  alias movements show
  alias statement show
  alias extracto show

  private

  def set_money_source
    @money_source = current_user.money_sources.find(params[:id])
  end

  def load_statement_context(paginate: true)
    @statement = MoneySources::Statement.new(
      user: current_user,
      source: @money_source,
      period: params[:period],
      start_date: params[:start_date],
      end_date: params[:end_date],
      kind: params[:kind],
      query: params[:q],
      page: params[:page],
      per_page: params[:per_page],
      paginate: paginate
    ).call
  end

  def send_statement_export(exporter, content_type)
    load_statement_context(paginate: false)
    send_data exporter.call(@statement),
              filename: exporter.filename(@statement),
              type: content_type,
              disposition: "attachment"
  end

  def not_found
    head :not_found
  end
end
