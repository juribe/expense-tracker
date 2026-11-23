# frozen_string_literal: true

class MoneySourceExtractsController < ApplicationController
  include MoneySourceShowContext

  before_action :authenticate_user!
  before_action :set_money_source
  before_action :authorize_statement_access

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
        @simple_money_view = money_tracking_simple? && @money_source.general?
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

  # Simple mode only exposes the statement of General. Any other source id is
  # rejected before rendering or exporting, so hiding the links is not the
  # only protection.
  def authorize_statement_access
    return if money_tracking_detailed?
    return if money_tracking_simple? && @money_source.general?

    redirect_to dashboard_path, alert: t("money_tracking.advanced_only")
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
