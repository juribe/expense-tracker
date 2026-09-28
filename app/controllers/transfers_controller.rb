# frozen_string_literal: true

class TransfersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_transfer, only: [ :destroy ]

  rescue_from ActiveRecord::RecordNotFound, with: :not_found

  # GET /transfers
  def index
    @transfers = current_user.transfers
      .includes(:from_source, :to_source)
      .order(date: :desc, created_at: :desc)
      .limit(50)
  end

  # GET /transfers/new
  def new
    @transfer = current_user.transfers.build(date: Date.current)
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
