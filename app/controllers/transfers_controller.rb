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
    @transfer = current_user.transfers.build(
      date: default_record_date,
      from_source_id: params[:from_source_id],
      to_source_id: params[:to_source_id],
      amount: params[:amount].present? ? MoneyFormat.normalize(params[:amount]) : nil
    )
    set_direction_sources
    set_pocket_goals
  end

  # POST /transfers
  def create
    @transfer = current_user.transfers.build(transfer_params)
    if @transfer.save
      allocate_transfer_to_goal(@transfer)
      redirect_to(safe_return_to.presence || transfers_path,
                  notice: t("transfers.flashes.created"))
    else
      set_direction_sources
      set_pocket_goals
      render :new, status: :unprocessable_entity
    end
  end

  # DELETE /transfers/1
  def destroy
    if @transfer.destroy
      redirect_to transfers_path, notice: t("transfers.flashes.deleted")
    else
      redirect_to transfers_path, alert: @transfer.errors.full_messages.first
    end
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
  #   from — pays out: payment sources, a revolving loan (the only kind
  #          allowed to disburse money), and pockets (releasing assigned
  #          money back / re-assigning it).
  #   to   — receives: payment sources, credit cards and loans (a transfer
  #          into a debt IS that debt's payment), and pockets (assigning
  #          money to them). A pocket can never fund a debt — the model
  #          validation pocket_flow_rules rejects that combination.
  def set_direction_sources
    # display_name touches credit_account for card digits; Bullet requires it eager-loaded.
    @from_sources = current_user.money_sources.active
                                .merge(MoneySource.payment_sources
                                                   .or(MoneySource.funding_sources)
                                                   .or(MoneySource.pockets))
                                .includes(:credit_account)
                                .order(:kind, :name)
    @to_sources = current_user.money_sources.active
                               .merge(MoneySource.payment_sources
                                                  .or(MoneySource.debt_payment_targets)
                                                  .or(MoneySource.pockets))
                               .includes(:credit_account)
                               .order(:kind, :name)
  end

  def set_transfer
    @transfer = current_user.transfers.find(params[:id])
  end

  def not_found
    head :not_found
  end

  def transfer_params
    permitted = params.require(:transfer)
                      .permit(:from_source_id, :to_source_id, :amount, :date, :note)
    if permitted[:amount].present?
      # Accepts both Colombian display format ("1.000.000,50") and the
      # machine format ("1000000.50") — see MoneyFormat.
      permitted[:amount] = MoneyFormat.normalize(permitted[:amount])
    end
    permitted
  end

  # Goals grouped by pocket for the optional "assign to goal" step: the user
  # can earmark the transferred money for one of the destiny pocket's goals
  # in the same action.
  def set_pocket_goals
    @pocket_goals = current_user.money_sources.pockets.active
                                .includes(:goals)
                                .order(:name)
  end

  # When the transfer targets a pocket and a goal was picked, reserve the
  # whole transferred amount for that goal. The transfer just raised the
  # pocket's balance, so the allocation always fits — and it never creates
  # an expense or a bank movement.
  def allocate_transfer_to_goal(transfer)
    return unless transfer.to_source&.pocket?
    return if assign_goal_id.blank?

    goal = current_user.goals.find_by(id: assign_goal_id)
    return unless goal && goal.pocket_id == transfer.to_source_id

    goal.goal_allocations.create!(
      pocket: goal.pocket,
      amount: transfer.amount,
      date: transfer.date,
      note: transfer.note.presence
    )
  end

  def assign_goal_id
    params[:transfer].present? ? params[:transfer][:assign_goal_id] : params[:assign_goal_id]
  end

  # Where to go back after creating a transfer (e.g. the goals page when the
  # transfer came from the "Assign money" modal). Only local paths are
  # honored to avoid open redirects.
  def safe_return_to
    return_to = params[:return_to].to_s
    return_to if return_to.start_with?("/") && !return_to.start_with?("//")
  end
end
