require "csv"

class ExpensesController < ApplicationController
  # Ensure the user is authenticated before any other filters or actions
  before_action :authenticate_user!

  # Load the expense record for actions that need it
  before_action :set_expense, only: [:show, :edit, :update, :destroy]

  # Load categories for forms and the index filter
  before_action :set_categories, only: [:index, :new, :create, :edit, :update]

  SORTABLE_COLUMNS = %w[date description category frequency amount].freeze
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
          @page_subtotal = @expenses.sum(:amount)
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
      redirect_to expenses_path, notice: 'Expense was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @expense.update(expense_params)
      redirect_to expenses_path(redirect_params), notice: 'Expense was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @expense.destroy
    redirect_to expenses_path(redirect_params), notice: 'Expense was successfully deleted.'
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

  private

  def set_expense
    @expense = current_user.expenses.find(params[:id])
  end

  def set_categories
    @categories = Category.all
  end

  def expense_params
    params.require(:expense).permit(:amount, :description, :date, :frequency, :category_id)
  end

  def filter_query
    params.permit(:category_id, :start_date, :end_date, :frequency, :min_amount, :max_amount).to_h
  end

  def redirect_params
    filter_query.merge(
      sort: params[:sort],
      dir: params[:dir],
      page: params[:page]
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
       params[:min_amount].to_d > params[:max_amount].to_d
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
    @expenses = @expenses.where(frequency: params[:frequency]) if params[:frequency].present?
    @expenses = @expenses.where("amount >= ?", params[:min_amount]) if params[:min_amount].present?
    @expenses = @expenses.where("amount <= ?", params[:max_amount]) if params[:max_amount].present?
  end

  def apply_sort
    order_column = @sort == "category" ? "categories.name" : "expenses.#{@sort}"
    @expenses = @expenses.order("#{order_column} #{@dir}")
  end

  def paginate_expenses
    @per_page = DEFAULT_PAGE_SIZE
    @total_pages = (@total_count.to_f / @per_page).ceil
    @total_pages = 1 if @total_pages.zero?
    @page = params[:page].to_i.positive? ? params[:page].to_i : 1
    @page = @total_pages if @page > @total_pages
    @offset = (@page - 1) * @per_page
    @expenses = @expenses.limit(@per_page).offset(@offset)
  end

  def render_csv(expenses)
    csv = CSV.generate(headers: true) do |rows|
      rows << %w[date description category frequency amount]
      expenses.find_each do |expense|
        rows << [
          expense.date,
          expense.description.to_s,
          expense.category&.name.to_s,
          expense.frequency,
          expense.amount.to_s
        ]
      end
    end
    send_data csv, filename: "expenses-#{Date.today}.csv", type: "text/csv"
  end
end