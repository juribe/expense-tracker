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
                  notice: t("recurring.template_created", label: @recurring_template.completed_action_label)
    else
      load_index_data
      @open_form_modal = true
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @recurring_template.update(update_params)
      redirect_to index_path,
                  notice: t("recurring.template_updated")
    else
      load_index_data
      @open_form_modal = true
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    @recurring_template.destroy
    redirect_to index_path,
                notice: t("recurring.template_deleted")
  end

  def process_transaction
    money_source = payment_money_source(params[:money_source_id])
    if money_source == :invalid
      redirect_to index_path,
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
      redirect_to index_path,
                  notice: t("recurring.processed_on",
                            action: @recurring_template.completed_action_label,
                            amount: number_to_currency(result.transaction.amount),
                            date: I18n.l(result.transaction.date, format: :long))
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
                notice: t("recurring.template_#{state}")
  end

  private

  def set_categories
    @categories = Category.for_user(current_user)
  end

  def load_index_data
    @recurring_templates = current_user.recurring_templates
                                       .includes(:category)
                                       .where(kind: template_kind)
                                       .ordered
    @current_period = Date.current.strftime("%Y-%m")

    # "Pagar"/"Recibir" modal: where the money comes from / lands. Only
    # payment sources — loans are never recipients of an income nor payers.
    @payment_sources = MoneySource.payment_origins(current_user)

    @status_filter = %w[all completed pending].include?(params[:status]) ? params[:status] : "all"
    if @status_filter != "all"
      @recurring_templates = @recurring_templates.select { |rt| rt.status_for(@current_period).to_s == @status_filter }
    end

    @total_count = @recurring_templates.size
    @filtered_total = @recurring_templates.sum(&:signed_amount)
  end

  # The money source chosen in the process modal. :invalid signals the
  # submitted id does not belong to the user or is not a payment source.
  def payment_money_source(raw_id)
    return nil if raw_id.blank?

    current_user.money_sources.active.payment_sources.find_by(id: raw_id) || :invalid
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
