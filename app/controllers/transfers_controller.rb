# frozen_string_literal: true

class TransfersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_transfer, only: [ :destroy ]

  # Quick-action forms (money sources): the origin is fixed by the card that
  # opened the modal, so the compact form renders no origin selector and the
  # withdraw variant fixes the cash destination as well. Each mode pairs an
  # origin kind with its destination pool — see Transfers::QuickActions.
  # The assign variant anchors on the DESTINATION instead: the pocket entry
  # points fix the pocket and the form only asks for the origin.
  QUICK_MODES = %w[withdraw transfer pocket advance disburse release assign].freeze

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

  # GET /transfers/quick_new
  #
  # Compact quick-action form for the money source cards: the origin is fixed
  # by the card that opened the modal (no selector is rendered for it), the
  # withdraw variant fixes the cash destination and the assign variant fixes
  # the pocket. Posting goes to the regular #create, so every model
  # validation, the balance sync and the goal allocation flow are the same
  # the old full form used.
  def quick_new
    @transfer = current_user.transfers.build(
      from_source_id: params[:from_source_id],
      to_source_id: params[:to_source_id],
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
      # Every form posts with the quick context now; a stray POST without it
      # has no form to fall back to.
      redirect_to transfers_path,
                  alert: t("transfers.quick.unavailable",
                           default: "Esa acción rápida no está disponible para esta fuente de dinero.")
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

  # ----- Quick actions (compact transfer forms) -----

  # Fills everything the compact quick form needs. Shared with #create so a
  # validation failure re-renders the same form plus its errors.
  def set_quick_form_context
    @mode = params[:mode].to_s if params[:mode].in?(QUICK_MODES)
    @source = current_user.money_sources.active
                          .find_by(id: params[:from_source_id].presence || @transfer&.from_source_id)
    @to_pocket = assign_pocket if @mode == "assign"
    @cash_destination = quick_cash_destination
    @quick_return_to = quick_return_to_value
    @quick_ready = quick_form_ready?
    return unless @quick_ready

    # Withdraw and assign know both ends up front: pin the fixed end onto the
    # form object so the hidden field carries it.
    @transfer.to_source_id = @cash_destination.id if @mode == "withdraw" && @transfer.to_source_id.blank?
    @transfer.to_source_id = @to_pocket.id if @mode == "assign"
    @from_sources = quick_from_sources if @mode == "assign"
    @to_sources = quick_to_sources if @mode != "assign"
    set_pocket_goals if @mode.in?(%w[pocket assign])
  end

  # Which quick modes a given context may perform. Origin-anchored modes
  # mirror the concept table in Transfers::QuickActions: only payment
  # sources move money around, cash cannot retire from itself (it deposits
  # instead), a card's only outgoing move is the advance, a revolving line
  # only disburses into accounts, a pocket only releases back into accounts
  # + cash, and a pocket can never receive directly from a debt
  # (pocket_flow_rules). Withdrawing additionally needs a live cash source
  # to receive the money. The destination-anchored assign mode only needs a
  # real pocket to fill.
  def quick_form_ready?
    return false if @mode.blank?

    case @mode
    when "assign" then @to_pocket.present?
    when "withdraw" then origin_ready? && !@source.cash? && !@source.debt? && @cash_destination.present?
    when "transfer" then origin_ready?
    when "pocket" then origin_ready? && !@source.debt?
    when "advance" then @source&.credit_card? == true
    when "disburse" then @source&.revolving? == true
    when "release" then @source&.pocket? == true
    else false
    end
  end

  def origin_ready?
    @source.present? && @source.payment_source?
  end

  # The pocket the destination-anchored assign mode fills: an active pocket
  # owned by the user. Anything else (account, debt, foreign id) is nil, so
  # the guard redirects with the unavailable alert.
  def assign_pocket
    current_user.money_sources.active.pockets
                .find_by(id: params[:to_source_id].presence || @transfer&.to_source_id)
  end

  # Assign-mode origins: every non-debt payment source. Pockets never fund a
  # pocket and a card/loan payment is never a plain transfer, so credit cards
  # and loans stay out of the pool.
  def quick_from_sources
    current_user.money_sources.active
                .by_kind(%w[account debit_card wallet cash])
                .includes(:credit_account)
                .order(:kind, :name)
  end

  # The cash money source quick transfers retire into. The first active one
  # by creation order; the withdraw button is simply not offered when none
  # exists (no account is ever created implicitly).
  def quick_cash_destination
    current_user.money_sources.active.by_kind("cash").order(:id).first
  end

  # Quick destinations, narrowed per mode from the concept table:
  #   pocket    — every pocket (the optional goal step follows on the form)
  #   advance   — normal accounts plus cash (a card advance lands on either)
  #   release   — normal accounts plus cash (pocket money comes back out)
  #   disburse  — normal accounts only; a revolving line never pays a debt
  #   transfer  — real money locations only. Cash is excluded (the withdraw
  #               variant covers it) and debts are excluded: paying a card or
  #               loan is a Payment, never a plain quick transfer.
  # The origin itself is always left out of the options.
  def quick_to_sources
    scope = current_user.money_sources.active
    if @mode == "pocket"
      scope.pockets.includes(:credit_account).order(:name)
    else
      # display_name touches credit_account for card digits; eager load it
      # to satisfy Bullet when rendering each destination badge.
      kinds = %w[account debit_card wallet]
      kinds << "cash" if @mode.in?(%w[advance release])
      scope.by_kind(kinds)
           .includes(:credit_account)
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
