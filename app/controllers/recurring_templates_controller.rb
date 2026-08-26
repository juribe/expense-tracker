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
                  notice: "Recurring #{@recurring_template.kind} was successfully created."
    else
      load_index_data
      @open_form_modal = true
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @recurring_template.update(update_params)
      redirect_to recurring_templates_path(kind: @recurring_template.kind),
                  notice: "Recurring #{@recurring_template.kind} was successfully updated."
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
                notice: "Recurring #{type} was successfully deleted."
  end

  # Receive (income) / Pay (expense): creates the real one-time transaction.
  def process_transaction
    result = RecurringTemplateProcessor.call(
      recurring_template: @recurring_template,
      amount: params[:amount],
      date: params[:date]
    )

    if result.success?
      redirect_to recurring_templates_path(kind: @recurring_template.kind),
                  notice: "#{@recurring_template.completed_action_label} #{number_to_currency(result.transaction.amount)} " \
                          "on #{result.transaction.date.strftime('%B %-d, %Y')}."
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
                notice: "Recurring #{@recurring_template.kind} was successfully #{state}."
  end

  private

  def set_categories
    @categories = Category.all
  end

  def set_money_sources
    @money_sources = current_user.money_sources.active.order(:kind, :name)
  end

  def load_index_data
    @kind = %w[income expense].include?(params[:kind]) ? params[:kind] : "income"
    @recurring_templates = current_user.recurring_templates
                                       .includes(:category, :transactions)
                                       .where(kind: @kind)
                                       .ordered
    @current_period = Date.current.strftime("%Y-%m")

    @status_filter = %w[all paid pending].include?(params[:status]) ? params[:status] : "all"
    if @status_filter != "all"
      @recurring_templates = @recurring_templates.select { |rt| rt.status_for(@current_period).to_s == @status_filter }
    end

    @total_count = @recurring_templates.size
    @filtered_total = @recurring_templates.sum(&:signed_amount)
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
