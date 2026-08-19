class ExpensesController < ApplicationController
  # Ensure the user is authenticated before any other filters or actions
  before_action :authenticate_user!

  # Load the expense record for actions that need it
  before_action :set_expense, only: [:show, :edit, :update, :destroy]

  # Load categories for forms that need to select a category
  before_action :set_categories, only: [:new, :create, :edit, :update]

  def index
    @expenses = current_user.expenses.includes(:category).order(date: :desc)

    # Apply filters if present
    @expenses = @expenses.by_category(params[:category_id]) if params[:category_id].present?
    @expenses = @expenses.where("date >= ?", params[:start_date]) if params[:start_date].present?
    @expenses = @expenses.where("date <= ?", params[:end_date]) if params[:end_date].present?
    @expenses = @expenses.where(frequency: params[:frequency]) if params[:frequency].present?
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
      redirect_to expenses_path, notice: 'Expense was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @expense.destroy
    redirect_to expenses_path, notice: 'Expense was successfully deleted.'
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
end