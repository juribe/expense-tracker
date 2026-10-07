# frozen_string_literal: true

class RecurringTemplatesController < ApplicationController
  include ActionView::Helpers::NumberHelper

  # Categories are needed whenever the index page (and its form modal) renders.
  before_action :set_categories, only: [ :index, :create, :update ]
  before_action :set_money_sources, only: [ :index, :create, :update ]
  before_action :load_index_data, only: [ :index ]
  before_action :set_recurring_template, only: [ :update, :destroy, :process_transaction, :toggle_active ]

  def index
    @recurring_template ||= current_user.recurring_templates.build(
      kind: @kind,
      active: true,
      payment_day: Date.current.day
    )
  end

  def create
    @recurring_template = current_user.recurring_templates.build(recurring_template_params)

    if @recurring_template.save
      redirect_to recurring_templates_path(kind: @recurring_template.kind),
                  notice: t("recurring.template_created", label: @recurring_template.completed_action_label)
    else
      load_index_data
      @open_form_modal = true
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @recurring_template.update(update_params)
      redirect_to recurring_templates_path(kind: @recurring_template.kind),
                  notice: t("recurring.template_updated")
    else
      load_index_data
      @open_form_modal = true
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    type = @recurring_template.kind
    @recurring_template.destroy
    redirect_to recurring_templates_path(kind: type),
                notice: t("recurring.template_deleted")
  end

  # Receive (income) / Pay (expense): creates the real one-time transaction.
  def process_transaction
    money_source = current_user.money_sources.active.payment_sources.find_by(id: params[:money_source_id].presence)
    if params[:money_source_id].present? && money_source.nil?
      redirect_to recurring_templates_path(kind: @recurring_template.kind),
                  alert: t("recurring.invalid_payment_source"),
                  status: :see_other
      return
    end

    result = RecurringTemplateProcessor.call(
      recurring_template: @recurring_template,
      amount: params[:amount],
      date: params[:date],
      money_source: money_source
    )

    if result.success?
      redirect_to recurring_templates_path(kind: @recurring_template.kind),
                  notice: t("recurring.processed_on",
                            action: @recurring_template.completed_action_label,
                            amount: number_to_currency(result.transaction.amount),
                            date: I18n.l(result.transaction.date, format: :long))
    else
      redirect_to recurring_templates_path(kind: @recurring_template.kind),
                  alert: result.error,
                  status: :see_other
    end
  end

  # Soft-disable / re-enable without deleting the configuration.
  def toggle_active
    @recurring_template.update!(active: !@recurring_template.active?)
    state = @recurring_template.active? ? "activated" : "deactivated"
    redirect_to recurring_templates_path(kind: @recurring_template.kind),
                notice: t("recurring.template_#{state}")
  end

  private

  def set_categories
    @categories = Category.for_user(current_user)
  end

  def set_money_sources
    # The index shows one template kind at a time. Income templates receive
    # money into an account/wallet/cash — loans never take an income.
    # Expense templates keep every source: a normal expense points at a
    # payment source, while a debt-payment cuota points at the loan/card
    # itself (debt_payment_target — see MoneySource).
    sources = current_user.money_sources.active.order(:kind, :name)
    @money_sources = params[:kind].to_s == "expense" ? sources : sources.payment_sources
  end

  def load_index_data
    @kind = %w[income expense].include?(params[:kind]) ? params[:kind] : "income"
    @recurring_templates = current_user.recurring_templates
                                       .includes(:category, :transactions)
                                       .where(kind: @kind)
                                       .ordered
    @current_period = current_listing_period

    # "Pagar"/"Recibir" modal: where the money comes from / lands. Only
    # payment sources — loans are never recipients of an income nor payers.
    @payment_sources = MoneySource.payment_origins(current_user)

    @status_filter = %w[all paid pending].include?(params[:status]) ? params[:status] : "all"
    if @status_filter != "all"
      @recurring_templates = @recurring_templates.select { |rt| rt.status_for(@current_period).to_s == @status_filter }
    end

    @total_count = @recurring_templates.size
    @filtered_total = @recurring_templates.sum(&:signed_amount)
  end

  # Mirrors RecurringTemplateActions#current_listing_period: a pay cycle for
  # users with configured paydays, or the legacy calendar-month string.
  def current_listing_period
    return Date.current.strftime("%Y-%m") unless Reports::Period.cycles_enabled?(current_user)

    anchor = params[:period].present? ? Date.parse(params[:period]) : Date.current
    PayCycle.containing(current_user, anchor)
  rescue ArgumentError, TypeError
    PayCycle.current(current_user)
  end

  # Owner-only authorization: scoping through current_user guarantees a user
  # can never load another user's recurring transaction.
  def set_recurring_template
    @recurring_template = current_user.recurring_templates.find(params[:id])
  end

  def recurring_template_params
    params.require(:recurring_template)
          .permit(:category_id, :kind, :amount, :description, :payment_day, :active, :money_source_id)
  end

  # The transaction type is immutable after creation so historical
  # occurrences stay consistent.
  def update_params
    params.require(:recurring_template)
          .permit(:category_id, :amount, :description, :payment_day, :active, :money_source_id)
  end
end
