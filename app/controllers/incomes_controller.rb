# frozen_string_literal: true

class IncomesController < ApplicationController
  # GET /incomes or /incomes.json
  def index
    @incomes = Income.for_user(current_user).recent(50)
  end

  # GET /incomes/new
  def new
    @income = Income.new
    assign_income_prefill
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
    # credit_account is eager loaded: display_name renders the card's last
    # four for credit cards (same pattern as MoneySource.payment_origins).
    current_user.money_sources.active.payment_sources.includes(:credit_account).order(:kind, :name)
  end

  def income_params
    params.require(:income).permit(:amount, :description, :date, :category_id, :money_source_id)
  end

  # Optional prefill for the standard new-income form, used when it is opened
  # from the Día de Cuadre reconciliation modal (amount/money source of the
  # difference). Only fills the form; creation still goes through create.
  def assign_income_prefill
    prefill = params.permit(:amount, :description, :money_source_id, :date)
    return if prefill.blank?

    @income.amount = prefill[:amount] if prefill[:amount].present?
    @income.description = prefill[:description] if prefill[:description].present?
    @income.date = prefill[:date] if prefill[:date].present?

    return if prefill[:money_source_id].blank?

    source = current_user.money_sources.find_by(id: prefill[:money_source_id])
    @income.money_source = source if source
  end
end
