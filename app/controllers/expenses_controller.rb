require "csv"

class ExpensesController < ApplicationController
  # Ensure the user is authenticated before any other filters or actions
  before_action :authenticate_user!

  # Load the expense record for actions that need it
  before_action :set_expense, only: [ :show, :edit, :update, :destroy ]

  # Load categories for forms and the index filter
  before_action :set_categories, only: [ :index, :new, :create, :edit, :update ]

  # Load money sources for forms and filters
  before_action :set_money_sources, only: [ :index, :new, :create, :edit, :update ]

  SORTABLE_COLUMNS = %w[date description category amount].freeze
  SORT_DIRECTIONS = %w[asc desc].freeze
  DEFAULT_SORT_DIR = { "date" => "desc", "amount" => "desc" }.freeze
  DEFAULT_PAGE_SIZE = 25

  def index
    @expenses = current_user.expenses.includes(:category)
    @sort = params[:sort].to_s
    @dir = params[:dir].to_s
    @sort = "date" unless SORTABLE_COLUMNS.include?(@sort)
    @dir = "desc" unless SORT_DIRECTIONS.include?(@dir)

    @filter_errors = validate_filters

    if @filter_errors.empty?
      apply_filters
      apply_sort

      respond_to do |format|
        format.csv { render_csv(@expenses) }
        format.html do
          @total_count = @expenses.count
          @filtered_total = @expenses.sum(:amount)
          paginate_expenses
          @page_subtotal = @expenses.sum(&:amount)
          render :index
        end
      end
    else
      # Invalid filter ranges: do not run the query; keep the form so the
      # user can correct the offending fields.
      @expenses = current_user.expenses.none
      @total_count = 0
      @filtered_total = 0
      @page_subtotal = 0
      @page = 1
      @offset = 0
      @total_pages = 1
      render :index
    end
  rescue ArgumentError, ActiveRecord::StatementInvalid, ActiveRecord::RecordNotFound
    @load_error = true
    @filter_errors = {}
    @expenses = Expense.none
    @total_count = 0
    @filtered_total = 0
    @page_subtotal = 0
    @page = 1
    @offset = 0
    @total_pages = 1
    render :index
  end

  def show
    render layout: false
  end

  def new
    @expense = current_user.expenses.build(date: Date.today)
  end

  def create
    @expense = current_user.expenses.build(expense_params)
    if @expense.save
      redirect_to expenses_path, notice: "Expense was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @expense.update(expense_params)
      redirect_to expenses_path(redirect_params), notice: "Expense was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @expense.destroy
    redirect_to expenses_path(redirect_params), notice: "Expense was successfully deleted."
  end

  def bulk_destroy
    ids = Array(params[:ids]).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?)
    scope = current_user.expenses.where(id: ids)
    count = scope.count

    if count.zero?
      redirect_to expenses_path(redirect_params), alert: "No expenses selected."
      return
    end

    failed = 0
    scope.find_each do |expense|
      begin
        expense.destroy!
      rescue ActiveRecord::RecordNotDestroyed
        failed += 1
      end
    end

    deleted = count - failed
    if failed.zero?
      redirect_to expenses_path(redirect_params), notice: "#{deleted} #{'expense'.pluralize(deleted)} deleted."
    else
      redirect_to expenses_path(redirect_params),
                  alert: "Deleted #{deleted} of #{count} expenses. #{failed} could not be deleted."
    end
  end

  # PATCH /expenses/bulk_update
  # Bulk-updates the category and/or money source of many expenses at once.
  def bulk_update
    raw = request.request_parameters
    ids = Array(raw["expense_ids"]).flat_map { |value| value.to_s.split(",") }.map(&:to_i).reject(&:zero?)
    category_id = raw["category_id"].presence
    money_source_id = raw["money_source_id"].presence

    if ids.empty?
      redirect_to expenses_path(bulk_update_state), alert: "No expenses selected."
      return
    end

    if category_id.blank? && money_source_id.blank?
      redirect_to expenses_path(bulk_update_state), alert: "Choose a category and/or money source to update."
      return
    end

    if category_id.present? && !Category.for_user(current_user).where(id: category_id).exists?
      redirect_to expenses_path(bulk_update_state),
                  alert: "Couldn't update expenses: category was not found for this user."
      return
    end

    if money_source_id.present? && !current_user.money_sources.where(id: money_source_id).exists?
      redirect_to expenses_path(bulk_update_state),
                  alert: "Couldn't update expenses: money source was not found for this user."
      return
    end

    scope = current_user.expenses.where(id: ids)
    count = scope.count
    if count.zero?
      redirect_to expenses_path(bulk_update_state), alert: "No expenses selected."
      return
    end

    updates = {}
    updates[:category_id] = category_id.to_i if category_id.present?
    updates[:money_source_id] = money_source_id.to_i if money_source_id.present?

    scope.update_all(updates)

    redirect_to expenses_path(bulk_update_state),
                notice: "#{count} #{'expense'.pluralize(count)} updated."
  end

  # POST /expenses/parse
  # Interprets natural language (typed or transcribed voice) WITHOUT persisting
  # anything. The user reviews/edits the detected expenses before saving them.
  def parse
    text = params[:text].presence || params[:transcription].presence
    if text.blank?
      return respond_parse_error("Please write or dictate your expenses first.")
    end

    result = ExpenseParser.call(text: text, user: current_user)

    respond_to do |format|
      format.json do
        if result[:expenses].any?
          render json: result, status: :ok
        else
          message = result[:errors].presence ||
                    "No expenses were detected. Try something like \"50 mil en almuerzo\"."
          render json: { engine: result[:engine], transcription: result[:transcription], expenses: [], errors: Array(message) },
                 status: :unprocessable_entity
        end
      end
      format.html { redirect_to expenses_path, alert: "Use the AI entry box to detect expenses." }
    end
  end

  # POST /expenses/bulk_create
  # Persists several confirmed expenses in a single action.
  def bulk_create
    inputs = bulk_expense_inputs
    if inputs.empty?
      return respond_bulk_error("No expenses to save.")
    end

    created_count = 0
    ActiveRecord::Base.transaction do
      inputs.each_with_index do |input, index|
        begin
          expense = build_expense_from_confirmed_input(input)
          unless expense.save
            raise ActiveRecord::RecordInvalid, row_error(expense, index)
          end
        rescue ArgumentError => e
          raise ArgumentError, "Expense #{index + 1}: #{e.message}"
        end
        created_count += 1
      end
    end

    respond_to do |format|
      format.json { render json: { created: created_count, redirect_to: expenses_url }, status: :created }
      format.html do
        redirect_to expenses_path, notice: "#{created_count} #{'expense'.pluralize(created_count)} created."
      end
    end
  rescue ArgumentError => e
    respond_bulk_error(e.message)
  rescue ActiveRecord::RecordInvalid => e
    respond_bulk_error(e.message)
  end

  private

  def set_expense
    @expense = current_user.expenses.find(params[:id])
  end

  def set_categories
    @categories = Category.for_user(current_user)
  end

  def set_money_sources
    @money_sources = current_user.money_sources.active.order(:kind, :name)
  end

  def expense_params
    params.require(:expense).permit(:amount, :description, :date, :category_id, :money_source_id)
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

  def validate_filters
    errors = {}
    if params[:start_date].present? && params[:end_date].present?
      if !valid_date?(params[:start_date])
        errors[:start_date] = "Enter a valid From date."
      elsif !valid_date?(params[:end_date])
        errors[:end_date] = "Enter a valid To date."
      elsif params[:start_date] > params[:end_date]
        errors[:start_date] = "From cannot be after To."
      end
    elsif params[:start_date].present? && !valid_date?(params[:start_date])
      errors[:start_date] = "Enter a valid From date."
    elsif params[:end_date].present? && !valid_date?(params[:end_date])
      errors[:end_date] = "Enter a valid To date."
    end

    if params[:min_amount].present? && params[:max_amount].present? &&
       money_value(params[:min_amount]) > money_value(params[:max_amount])
      errors[:min_amount] = "Min amount cannot exceed Max amount."
    end
    errors
  end

  def valid_date?(value)
    Date.iso8601(value.to_s)
    true
  rescue ArgumentError
    false
  end

  def apply_filters
    @expenses = @expenses.in_category(params[:category_id]) if params[:category_id].present?
    @expenses = @expenses.where("date >= ?", params[:start_date]) if params[:start_date].present?
    @expenses = @expenses.where("date <= ?", params[:end_date]) if params[:end_date].present?
    @expenses = @expenses.where("ABS(amount) >= ?", money_value(params[:min_amount])) if params[:min_amount].present?
    @expenses = @expenses.where("ABS(amount) <= ?", money_value(params[:max_amount])) if params[:max_amount].present?
    @expenses = @expenses.where(money_source_id: params[:money_source_id]) if params[:money_source_id].present?
  end

  def apply_sort
    if @sort == "category"
      @expenses = @expenses.left_joins(:category).order("categories.name #{@dir}")
    elsif @sort == "amount"
      @expenses = @expenses.order(Arel.sql("ABS(#{Expense.table_name}.amount) #{@dir}"))
    else
      @expenses = @expenses.order("#{Expense.table_name}.#{@sort} #{@dir}")
    end
  end

  def paginate_expenses
    @per_page = DEFAULT_PAGE_SIZE
    @total_pages = (@total_count.to_f / @per_page).ceil
    @total_pages = 1 if @total_pages.zero?
    @page = params[:page].to_i.positive? ? params[:page].to_i : 1
    @page = @total_pages if @page > @total_pages
    @offset = (@page - 1) * @per_page
    @expenses = @expenses.limit(@per_page).offset(@offset).to_a
  end

  def render_csv(expenses)
    csv = CSV.generate(headers: true) do |rows|
      rows << %w[date description category amount source]
      expenses.find_each do |expense|
        rows << [
          expense.date,
          expense.description.to_s,
          expense.category&.name.to_s,
          expense.amount.to_s,
          expense.money_source&.name.to_s
        ]
      end
    end
    send_data csv, filename: "expenses-#{Date.today}.csv", type: "text/csv"
  end

  def money_value(value)
    return nil if value.blank?

    BigDecimal(value.to_s.delete(","))
  rescue ArgumentError, TypeError
    nil
  end

  # ------------------------------------------------------- ai entry helpers

  def respond_parse_error(message)
    respond_to do |format|
      format.json { render json: { expenses: [], errors: [ message ] }, status: :unprocessable_entity }
      format.html do
        redirect_to expenses_path, alert: message
      end
    end
  end

  def bulk_expense_inputs
    raw = params[:expenses]
    raw = raw.values if raw.is_a?(ActionController::Parameters)
    Array(raw).filter_map do |input|
      next if input.blank?

      source = input.respond_to?(:to_unsafe_h) ? input.to_unsafe_h : input
      ActionController::Parameters.new(source).permit(
        :amount, :description, :date, :transaction_date, :category_id, :new_category_name, :confidence, :money_source_id
      ).to_h
    end
  end

  def build_expense_from_confirmed_input(input)
    amount = money_value(input[:amount])
    raise ArgumentError, "Amount is required." if amount.nil?
    raise ArgumentError, "Amount must be greater than zero." unless amount.positive?

    date = parse_confirmed_date(input[:transaction_date].presence || input[:date])

    money_source = nil
    if input[:money_source_id].present?
      money_source = current_user.money_sources.find(input[:money_source_id])
    end

    Expense.new(
      user: current_user,
      category: resolve_confirmed_category!(input),
      amount: amount,
      description: input[:description].to_s.presence,
      date: date,
      source: "ai",
      money_source: money_source
    )
  end

  def parse_confirmed_date(value)
    return Date.current if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    raise ArgumentError, "Date is invalid."
  end

  def resolve_confirmed_category!(input)
    category_id = input[:category_id]
    new_name = input[:new_category_name].to_s.strip

    if category_id.present?
      Category.find(category_id)
    elsif new_name.present?
      Category.find_by(name: new_name) ||
        Category.where("lower(name) = ?", new_name.downcase).first ||
        Category.create!(name: new_name, user: current_user, is_default: false)
    else
      raise ArgumentError, "A category is required."
    end
  end

  def row_error(expense, index)
    details = expense.errors.full_messages.join(", ")
    "Expense #{index + 1}: #{details.presence || 'could not be saved'}."
  end

  def respond_bulk_error(message)
    respond_to do |format|
      format.json { render json: { errors: [ message ] }, status: :unprocessable_entity }
      format.html { redirect_to expenses_path, alert: message }
    end
  end
end
