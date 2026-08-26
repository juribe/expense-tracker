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
    @money_sources = current_user.money_sources.active.order(:kind, :name)
  end

  # POST /transfers
  def create
    @transfer = current_user.transfers.build(transfer_params)
    if @transfer.save
      redirect_to transfers_path, notice: "Transfer was successfully created."
    else
      @money_sources = current_user.money_sources.active.order(:kind, :name)
      render :new, status: :unprocessable_entity
    end
  end

  # DELETE /transfers/1
  def destroy
    @transfer.destroy
    redirect_to transfers_path, notice: "Transfer was successfully deleted."
  end

  private

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
