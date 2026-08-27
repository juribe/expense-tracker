# frozen_string_literal: true

module RecurringTemplateActions
  extend ActiveSupport::Concern

  included do
    before_action :set_categories, only: %i[index create update]
    before_action :load_index_data, only: [ :index ]
    before_action :set_recurring_template, only: %i[update destroy process_transaction toggle_active]
  end

  def index
    @recurring_template ||= current_user.recurring_templates.build(
      kind: template_kind,
      active: true,
      payment_day: Date.current.day
    )
  end

  def create
    @recurring_template = current_user.recurring_templates.build(recurring_template_params.merge(kind: template_kind))

    if @recurring_template.save
      redirect_to index_path,
                  notice: "#{@recurring_template.completed_action_label} recurring template was successfully created."
    else
      load_index_data
      @open_form_modal = true
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @recurring_template.update(update_params)
      redirect_to index_path,
                  notice: "Recurring template was successfully updated."
    else
      load_index_data
      @open_form_modal = true
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @recurring_template.destroy
    redirect_to index_path,
                notice: "Recurring template was successfully deleted."
  end

  def process_transaction
    result = RecurringTemplateProcessor.call(
      recurring_template: @recurring_template,
      amount: params[:amount],
      date: params[:date]
    )

    if result.success?
      redirect_to index_path,
                  notice: "#{@recurring_template.completed_action_label} #{number_to_currency(result.transaction.amount)} " \
                          "on #{result.transaction.date.strftime('%B %-d, %Y')}."
    else
      redirect_to index_path,
                  alert: result.error,
                  status: :see_other
    end
  end

  def toggle_active
    @recurring_template.update!(active: !@recurring_template.active?)
    state = @recurring_template.active? ? "activated" : "deactivated"
    redirect_to index_path,
                notice: "Recurring template was successfully #{state}."
  end

  private

  def set_categories
    @categories = Category.for_user(current_user)
  end

  def load_index_data
    @recurring_templates = current_user.recurring_templates
                                       .includes(:category, :transactions)
                                       .where(kind: template_kind)
                                       .ordered
    @current_period = Date.current.strftime("%Y-%m")

    @status_filter = %w[all completed pending].include?(params[:status]) ? params[:status] : "all"
    if @status_filter != "all"
      @recurring_templates = @recurring_templates.select { |rt| rt.status_for(@current_period).to_s == @status_filter }
    end

    @total_count = @recurring_templates.size
    @filtered_total = @recurring_templates.sum(&:signed_amount)
  end

  def set_recurring_template
    @recurring_template = current_user.recurring_templates.find(params[:id])
  end

  def recurring_template_params
    params.require(:recurring_template)
          .permit(:category_id, :kind, :amount, :description, :payment_day, :active)
  end

  def update_params
    params.require(:recurring_template)
          .permit(:category_id, :amount, :description, :payment_day, :active)
  end

  def index_path
    raise NotImplementedError, "Subclass must implement index_path"
  end

  def template_kind
    raise NotImplementedError, "Subclass must implement template_kind"
  end
end
