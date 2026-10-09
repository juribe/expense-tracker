# frozen_string_literal: true

class TransfersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_transfer, only: [ :destroy ]

  # Quick-action forms (money sources): the origin is fixed by the card that
  # opened the modal, so the compact form renders no origin selector and the
  # withdraw variant fixes the cash destination as well.
  QUICK_MODES = %w[withdraw transfer pocket].freeze

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

  # GET /transfers/quick_new
  #
  # Compact quick-action form for the money source cards: the origin is fixed
  # by the card that opened the modal (no selector is rendered for it) and the
  # withdraw variant fixes the cash destination too. Posting goes to the
  # regular #create, so every model validation, the balance sync and the goal
  # allocation flow are the same the full form uses.
  def quick_new
    @transfer = current_user.transfers.build(
      from_source_id: params[:from_source_id],
      date: Date.current
    )
    set_quick_form_context
    return redirect_quick_unavailable unless @quick_ready

    render :quick_new, layout: !quick_ajax?
  end

  # POST /transfers
  def create
    @transfer = current_user.transfers.build(transfer_params)
    if @transfer.save
      allocate_transfer_to_goal(@transfer)
      redirect_to(safe_return_to.presence || transfers_path,
                  notice: t("transfers.flashes.created"))
    elsif params[:quick].present?
      set_quick_form_context
      return redirect_quick_unavailable unless @quick_ready

      # The modal fetch swaps the bare fragment back in; with JS unavailable
      # the browser gets the standalone page (same layout as every other form).
      render :quick_new, layout: !quick_ajax?, status: :unprocessable_entity
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

  # ----- Quick actions (compact transfer forms from a fixed origin) -----

  # Fills everything the compact quick form needs. Shared with #create so a
  # validation failure re-renders the same form plus its errors.
  def set_quick_form_context
    @mode = params[:mode].to_s if params[:mode].in?(QUICK_MODES)
    @source = current_user.money_sources.active
                          .find_by(id: params[:from_source_id].presence || @transfer&.from_source_id)
    @cash_destination = quick_cash_destination
    @quick_return_to = quick_return_to_value
    @quick_ready = quick_form_ready?
    return unless @quick_ready

    # Withdraw knows both ends up front: pin the cash destination onto the
    # form object so the hidden field carries it.
    @transfer.to_source_id = @cash_destination.id if @mode == "withdraw" && @transfer.to_source_id.blank?
    @to_sources = quick_to_sources
    set_pocket_goals if @mode == "pocket"
  end

  # Which quick modes a given origin may perform. Borrowed straight from the
  # model's capabilities: only payment sources can send money; cash cannot
  # retire from itself (it deposits instead); a pocket can never receive
  # directly from a debt (pocket_flow_rules); withdrawing needs a live cash
  # source to receive the money.
  def quick_form_ready?
    return false if @source.blank? || !@source.payment_source? || @mode.blank?

    case @mode
    when "withdraw" then !@source.cash? && !@source.debt? && @cash_destination.present?
    when "pocket" then !@source.debt?
    else true
    end
  end

  # The cash money source quick transfers retire into. The first active one
  # by creation order; the withdraw button is simply not offered when none
  # exists (no account is ever created implicitly).
  def quick_cash_destination
    current_user.money_sources.active.by_kind("cash").order(:id).first
  end

  # Quick destinations, narrowed from the full form's direction pools:
  #   pocket    — every pocket (the optional goal step follows on the form)
  #   transfer  — real money locations only. Cash is excluded (the withdraw
  #               variant covers it) and debts are excluded: paying a card or
  #               loan is a Payment, never a plain quick transfer.
  # The origin itself is always left out of the options.
  def quick_to_sources
    scope = current_user.money_sources.active
    if @mode == "pocket"
      scope.pockets.order(:name)
    else
      scope.by_kind(%w[account debit_card wallet])
           .where.not(id: @source.id)
           .order(:name)
    end
  end

  # Same shape as safe_return_to: only local paths are honored.
  def quick_return_to_value
    raw = params[:return_to].to_s
    raw if raw.start_with?("/") && !raw.start_with?("//")
  end

  # The modal fetch tags itself with XHR: the quick templates then render as
  # a bare fragment (layout: false). Anything else — direct URL, JS off —
  # gets the regular layout. `layout: !quick_ajax?` picks between both.
  def quick_ajax?
    request.headers["X-Requested-With"] == "XMLHttpRequest"
  end

  # Direct-entry guard: the cards only ever render valid actions, so an
  # unsupported combination (or another user's source) lands here with a
  # clear alert instead of a form.
  def redirect_quick_unavailable
    redirect_to(quick_return_to_value.presence || transfers_path,
                alert: t("transfers.quick.unavailable", default: "Esa acción rápida no está disponible para esta fuente de dinero."))
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
