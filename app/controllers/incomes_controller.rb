# frozen_string_literal: true

class IncomesController < ApplicationController
  before_action :load_monthly_income_plans, only: :index

  # GET /incomes or /incomes.json
  def index
    @incomes = Income.for_user(current_user).recent(50)
  end

  # GET /incomes/new
  def new
    @income = Income.new
  end

  # POST /incomes or /incomes.json
  def create
    @income = Income.new(income_params)
    @income.user = current_user

    if @income.save
      redirect_to incomes_path, notice: "Income was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def income_params
    params.require(:income).permit(:amount, :description, :date, :category_id, :frequency)
  end

  def load_monthly_income_plans
    @monthly_income_plans = current_user.recurring_transactions
                                       .includes(:category, :occurrences)
                                       .of_type("income")
                                       .ordered
    @current_period = Date.current.strftime("%Y-%m")
  end

end
