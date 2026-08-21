# frozen_string_literal: true

class MonthlyExpensesController < ApplicationController
  before_action :set_monthly_expense, only: %i[show edit update destroy pay]

  def index
    @monthly_expenses = current_user.monthly_expenses
                                    .includes(:category, :monthly_expense_payments)
                                    .ordered
    @today = Date.current
  end

  def show; end

  def new
    @monthly_expense = current_user.monthly_expenses.new(payment_day: Date.current.day)
    load_categories
  end

  def create
    @monthly_expense = current_user.monthly_expenses.new(monthly_expense_params)
    if @monthly_expense.save
      redirect_to monthly_expenses_path, notice: "Monthly expense was successfully created."
    else
      load_categories
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_categories
  end

  def update
    if @monthly_expense.update(monthly_expense_params)
      redirect_to monthly_expenses_path, notice: "Monthly expense was successfully updated."
    else
      load_categories
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @monthly_expense.destroy
    redirect_to monthly_expenses_path, notice: "Monthly expense was successfully deleted."
  end

  # POST /monthly_expenses/:id/pay
  # Creates a regular Expense for the selected month and links it back to
  # this configuration. Duplicate payments for the same month are rejected.
  def pay
    payment_date = parse_payment_date
    return if performed?

    begin
      @monthly_expense.pay!(
        payment_date: payment_date,
        amount_override: params.dig(:monthly_expense_payment, :amount).presence&.to_d
      )
      redirect_to monthly_expenses_path,
                  notice: "Payment recorded for #{payment_date.strftime('%B %Y')}."
    rescue MonthlyExpense::PaymentError => e
      redirect_to monthly_expenses_path, alert: e.message
    end
  end

  private

  # Authorization: only the owner can manage or pay a monthly expense.
  def set_monthly_expense
    @monthly_expense = current_user.monthly_expenses.find(params[:id])
  end

  def load_categories
    @categories = Category.all
  end

  def monthly_expense_params
    params.require(:monthly_expense).permit(:category_id, :description, :amount, :payment_day, :active)
  end

  def parse_payment_date
    value = params.dig(:monthly_expense_payment, :payment_date).presence
    return Date.current if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    redirect_to monthly_expenses_path, alert: "Enter a valid payment date."
    nil
  end
end
