# frozen_string_literal: true

class IncomesController < ApplicationController
  # GET /incomes or /incomes.json
  def index
    @incomes = Income.for_user(current_user).recent(50)
  end

  # GET /incomes/new
  def new
    @income = Income.new
    @categories = Category.for_user(current_user)
    @money_sources = money_in_sources
  end

  # POST /incomes or /incomes.json
  def create
    @income = Income.new(income_params)
    @income.user = current_user

    if @income.save
      redirect_to incomes_path, notice: t("incomes.flashes.created")
    else
      @categories = Category.for_user(current_user)
      @money_sources = money_in_sources
      render :new, status: :unprocessable_entity
    end
  end

  private

  # An income lands in a source you can hold/spend from (account, wallet,
  # cash, debito card). Loans never receive an income.
  def money_in_sources
    current_user.money_sources.active.payment_sources.order(:kind, :name)
  end

  def income_params
    params.require(:income).permit(:amount, :description, :date, :category_id, :money_source_id)
  end
end
