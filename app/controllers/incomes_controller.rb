# frozen_string_literal: true

class IncomesController < ApplicationController
  # GET /incomes or /incomes.json
  def index
    @incomes = Income.for_user(current_user).recent(50)
  end

  # GET /incomes/new
  def new
    @income = Income.new
    @money_sources = current_user.money_sources.active.order(:kind, :name)
  end

  # POST /incomes or /incomes.json
  def create
    @income = Income.new(income_params)
    @income.user = current_user

    if @income.save
      redirect_to incomes_path, notice: "Income was successfully created."
    else
      @money_sources = current_user.money_sources.active.order(:kind, :name)
      render :new, status: :unprocessable_entity
    end
  end

  private

  def income_params
    params.require(:income).permit(:amount, :description, :date, :category_id, :money_source_id)
  end
end
