# frozen_string_literal: true

class TransfersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_transfer, only: [ :destroy ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # GET /transfers
  def index
    @span, @period_label, @cycle = transfer_period
    @start_date = params[:start_date]
    @end_date = params[:end_date]
    @transfers = current_user.transfers
      .includes(:from_source, :to_source)
      .where(date: @span)
      .order(date: :desc, created_at: :desc)
      .limit(50)
  end

  # GET /transfers/new
  def new
    @transfer = current_user.transfers.build(date: default_record_date)
    set_direction_sources
  end

  # POST /transfers
  def create
    @transfer = current_user.transfers.build(transfer_params)
    if @transfer.save
      redirect_to transfers_path, notice: t("transfers.flashes.created")
    else
      set_direction_sources
      render :new, status: :unprocessable_entity
    end
  end

  # DELETE /transfers/1
  def destroy
    @transfer.destroy
    redirect_to transfers_path, notice: t("transfers.flashes.deleted")
  end

  private

  # The list's date span: explicit start/end form bounds win; otherwise the
  # current financial cycle with a configured cycle or the plain calendar
  # month. The cycle (or nil) backs the cycle badge in the page title.
  def transfer_period
    if params[:start_date].present? || params[:end_date].present?
      start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : Date.current.beginning_of_month
      end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current
      return [ start_date..end_date,
               "#{I18n.l(start_date)} – #{I18n.l(end_date)}", nil ]
    end

    anchor = params[:cycle].present? ? Date.parse(params[:cycle]) : Date.current
    if Reports::Period.cycles_enabled?(current_user)
      cycle = PayCycle.containing(current_user, anchor)
      [ cycle.to_range, cycle.label, cycle ]
    else
      month = anchor.beginning_of_month
      [ month..month.end_of_month, I18n.l(month, format: :month_year), nil ]
    end
  rescue ArgumentError, TypeError
    flash.now[:alert] = t("transfers.index.invalid_dates", default: "Las fechas del filtro no son válidas; se muestra el período actual.")
    params.delete(:start_date)
    params.delete(:end_date)
    params.delete(:cycle)
    transfer_period
  end

  # Each end of the transfer offers only the sources the operation allows
  # (see MoneySource capabilities):
  #   from — pays out: payment sources, plus a revolving loan (which is the
  #          only kind allowed to disburse money).
  #   to   — receives: payment sources, plus credit cards and loans (a
  #          transfer into a debt IS that debt's payment).
  def set_direction_sources
    @from_sources = current_user.money_sources.active
                                .merge(MoneySource.payment_sources.or(MoneySource.funding_sources))
                                .order(:kind, :name)
    @to_sources = current_user.money_sources.active
                               .merge(MoneySource.payment_sources.or(MoneySource.debt_payment_targets))
                               .order(:kind, :name)
  end

  def set_transfer
    @transfer = current_user.transfers.find(params[:id])
  end

  def not_found
    head :not_found
  end

  def transfer_params
    params.require(:transfer).permit(:from_source_id, :to_source_id, :amount, :date, :note)
  end
end
