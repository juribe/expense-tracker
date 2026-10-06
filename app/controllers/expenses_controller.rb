class ExpensesController < ApplicationController
  # Ensure the user is authenticated before any other filters or actions
  before_action :authenticate_user!

  # Load the expense record for actions that need it
  before_action :set_expense, only: [ :show, :edit, :update, :destroy ]

  # Load categories for forms and the index filter
  before_action :set_categories, only: [ :index, :new, :create, :edit, :update ]

  # Load money sources for forms and filters
  before_action :set_money_sources, only: [ :index, :new, :create, :edit, :update ]

  # Active expense recurring templates for the "apply to recurring" modal
  before_action :set_recurring_templates, only: [ :index ]

  def index
    search = Expenses::Search.call(user: current_user, params: params)

    @sort = search.sort
    @dir = search.dir
    @filter_errors = search.filter_errors

    respond_to do |format|
      format.csv do
        render_csv(search.csv_scope)
      end
      format.html do
        @expenses = search.relation
        @total_count = search.total_count
        @filtered_total = search.filtered_total
        @page_subtotal = search.page_subtotal
        render :index
      end
    end
  rescue ArgumentError, ActiveRecord::StatementInvalid, ActiveRecord::RecordNotFound
    @load_error = true
    @filter_errors = {}
    @expenses = Expense.none
    @total_count = 0
    @filtered_total = 0
    @page_subtotal = 0
    render :index
  end

  def show
    render layout: false
  end

  def new
    @expense = current_user.expenses.build(date: Date.today)
    assign_expense_prefill
  end

  def create
    @expense = current_user.expenses.build(expense_params)
    if @expense.save
      redirect_to expenses_path, notice: t("expenses.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @expense.update(expense_params)
      redirect_to expenses_path(redirect_params), notice: t("expenses.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @expense.destroy
    redirect_to expenses_path(redirect_params), notice: t("expenses.deleted")
  end

  # POST /expenses/assign_recurring
  # Assigns ONE existing expense (e.g. imported from an email statement) to an
  # active expense recurring template. The template reads its own status from
  # its linked transactions, so the assigned expense immediately marks that
  # month as "Pagado" — the same effect the processor's generated payment has.
  # This is only the template association: no Payment is created and no
  # credit balance changes (apply payments from the credit/loan page).
  def assign_recurring
    result = Expenses::RecurringAssignment.assign(
      user: current_user,
      expense_id: params[:expense_id],
      recurring_template_id: params[:recurring_template_id]
    )

    if result.success?
      redirect_to expenses_path(bulk_update_state),
                  notice: t("expenses.assign_recurring.applied", description: result.description)
    else
      redirect_to expenses_path(bulk_update_state),
                  alert: t("expenses.assign_recurring.#{result.message_key}", description: result.description)
    end
  end

  # POST /expenses/unassign_recurring
  # Clears the recurring-template assignment of a single expense; the template
  # falls back to "Pendiente" for the period the expense had covered.
  def unassign_recurring
    result = Expenses::RecurringAssignment.unassign(user: current_user, expense_id: params[:expense_id])

    if result.success?
      redirect_to expenses_path(bulk_update_state), notice: t("expenses.assign_recurring.unlinked")
    else
      redirect_to expenses_path(bulk_update_state), alert: t("expenses.assign_recurring.not_linked")
    end
  end

  def bulk_destroy
    result = Expenses::BulkDestroy.call(user: current_user, ids: params[:ids])

    if result.failure?
      redirect_to expenses_path(redirect_params), alert: t("expenses.no_selection")
      return
    end

    if result.failed_count.zero?
      redirect_to expenses_path(redirect_params), notice: t("expenses.bulk_deleted", count: result.deleted_count)
    else
      redirect_to expenses_path(redirect_params),
                  alert: t("expenses.bulk_deleted_partial",
                           deleted: result.deleted_count,
                           count: result.deleted_count + result.failed_count,
                           failed: result.failed_count)
    end
  end

  # PATCH /expenses/bulk_update
  # Bulk-updates the category and/or money source of many expenses at once.
  def bulk_update
    raw = request.request_parameters
    result = Expenses::BulkUpdate.call(
      user: current_user,
      ids: raw["expense_ids"],
      category_id: raw["category_id"],
      money_source_id: raw["money_source_id"]
    )

    case result.error_key
    when nil
      redirect_to expenses_path(bulk_update_state), notice: t("expenses.bulk_updated", count: result.updated_count)
    when :no_selection
      redirect_to expenses_path(bulk_update_state), alert: t("expenses.no_selection")
    when :nothing_to_change
      redirect_to expenses_path(bulk_update_state), alert: t("expenses.choose_category_or_source")
    when :category_not_found
      redirect_to expenses_path(bulk_update_state), alert: t("expenses.update_category_not_found")
    when :source_not_found
      redirect_to expenses_path(bulk_update_state), alert: t("expenses.update_source_not_found")
    end
  end

  # POST /expenses/parse
  # Interprets natural language (typed or transcribed voice) WITHOUT persisting
  # anything. The user reviews/edits the detected expenses before saving them.
  def parse
    text = params[:text].presence || params[:transcription].presence
    if text.blank?
      return respond_parse_error(t("expenses.ai_write_first"))
    end

    result = ExpenseResolver::Service.call(text: text, user: current_user)

    respond_to do |format|
      format.json do
        expenses = result.success? ? ExpenseResolver::Serializer.call(result.result) : []
        if expenses.any?
          render json: { transcription: text, expenses: expenses, errors: [] }, status: :ok
        else
          message = result.failure? ? result.errors : t("expenses.ai_no_expenses_hint")
          render json: { transcription: text, expenses: [], errors: Array(message) },
                 status: :unprocessable_entity
        end
      end
      format.html { redirect_to expenses_path, alert: t("expenses.ai_use_entry_box") }
    end
  end

  # POST /expenses/bulk_create
  # Persists several confirmed expenses in a single action.
  def bulk_create
    result = Expenses::BulkCreate.call(user: current_user, inputs: params[:expenses])

    if result.failure?
      return respond_bulk_error(result.error_message)
    end

    respond_to do |format|
      format.json { render json: { created: result.created_count, redirect_to: expenses_url }, status: :created }
      format.html do
        redirect_to expenses_path, notice: t("expenses.bulk_created", count: result.created_count)
      end
    end
  end

  private

  def set_expense
    @expense = current_user.expenses.find(params[:id])
  end

  def set_categories
    @categories = Category.for_user(current_user)
  end

  def set_money_sources
    @money_sources = MoneySource.payment_origins(current_user)
  end

  # Active expense recurring templates for the "assign to recurring" modal,
  # plus the ids already paid this period — those render disabled, since an
  # expense must first be unassigned to reopen the period.
  def set_recurring_templates
    # Debt payments (credit cards / loans) are applied from their money
    # source page — a single-link assign would skip the real Payment. Their
    # templates never appear in the assign modal.
    @recurring_templates = current_user.recurring_templates.active.expense
                                       .includes(:category, :money_source).ordered
                                       .reject { |template| template.money_source&.debt_payment_target? }
    month_range = Date.current.beginning_of_month..Date.current.end_of_month
    @paid_template_ids = Transaction.where(recurring_template_id: @recurring_templates, date: month_range)
                                    .distinct.pluck(:recurring_template_id)
  end

  def expense_params
    params.require(:expense).permit(:amount, :description, :date, :category_id, :money_source_id)
  end

  # Optional prefill for the standard new-expense form, used when it is opened
  # from the Día de Cuadre reconciliation modals (amount/money source of the
  # difference). Only fills the form; creation still goes through create.
  def assign_expense_prefill
    prefill = params.permit(:amount, :description, :money_source_id, :date)
    return if prefill.blank?

    @expense.amount = prefill[:amount] if prefill[:amount].present?
    @expense.description = prefill[:description] if prefill[:description].present?
    @expense.date = prefill[:date] if prefill[:date].present?

    return if prefill[:money_source_id].blank?

    source = current_user.money_sources.find_by(id: prefill[:money_source_id])
    @expense.money_source = source if source
  end

  def filter_query
    params.permit(:category_id, :start_date, :end_date, :min_amount, :max_amount, :money_source_id).to_h
  end

  def redirect_params
    filter_query.merge(
      sort: params[:sort],
      dir: params[:dir],
      page: params[:page]
    ).compact_blank
  end

  # State (filters, sort, pagination) for bulk_update redirects. Read from the
  # query string only, so the update fields in the request body (category_id /
  # money_source_id) never collide with the preserved filter values.
  def bulk_update_state
    request.query_parameters.slice(
      "category_id", "money_source_id", "start_date", "end_date",
      "min_amount", "max_amount", "sort", "dir", "page"
    ).compact_blank
  end

  def render_csv(expenses)
    send_data Expenses::CsvExporter.call(expenses),
              filename: Expenses::CsvExporter.filename, type: "text/csv"
  end

  def respond_parse_error(message)
    respond_to do |format|
      format.json { render json: { expenses: [], errors: [ message ] }, status: :unprocessable_entity }
      format.html do
        redirect_to expenses_path, alert: message
      end
    end
  end

  def respond_bulk_error(message)
    respond_to do |format|
      format.json { render json: { errors: [ message ] }, status: :unprocessable_entity }
      format.html { redirect_to expenses_path, alert: message }
    end
  end
end
