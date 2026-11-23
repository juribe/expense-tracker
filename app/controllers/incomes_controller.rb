# frozen_string_literal: true

class IncomesController < ApplicationController
  # GET /incomes or /incomes.json
  def index
    @period = PayCycle.current(current_user)
    @date_filter_applied = params[:start_date].present? || params[:end_date].present?
    @cycle_filter = cycle_filter
    @filter_errors = date_filter_errors
    @categories = Category.for_user_and_type(current_user, "income")
    @filters_applied = params[:q].present? || params[:category_id].present? || @date_filter_applied
    @incomes = filtered_incomes.recent(50)
    @filtered_count = filtered_incomes.count
    @summary = income_summary
  end

  # GET /incomes/new
  def new
    @income = Income.new(date: Date.current)
    assign_income_prefill
    @categories = Category.for_user_and_type(current_user, "income")
    @money_sources = money_in_sources
  end

  # POST /incomes or /incomes.json
  def create
    @income = Income.new(income_params)
    @income.user = current_user

    if @income.save
      redirect_to incomes_path, notice: t("incomes.flashes.created")
    else
      @categories = Category.for_user_and_type(current_user, "income")
      @money_sources = money_in_sources
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @income = current_user.incomes.find(params[:id])
    @categories = Category.for_user_and_type(current_user, "income")
    @money_sources = money_in_sources
  end

  def update
    @income = current_user.incomes.find(params[:id])
    if @income.update(income_params)
      redirect_to incomes_path, notice: t("incomes.flashes.updated")
    else
      @categories = Category.for_user_and_type(current_user, "income")
      @money_sources = money_in_sources
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @income = current_user.incomes.find(params[:id])
    @income.destroy
    redirect_to incomes_path, notice: t("incomes.flashes.deleted")
  end

  private

  # An income lands in a source you can hold/spend from (account, wallet,
  # cash, debito card). Loans never receive an income.
  def money_in_sources
    return [] if money_tracking_simple?

    # credit_account is eager loaded: display_name renders the card's last
    # four for credit cards (same pattern as MoneySource.payment_origins).
    current_user.money_sources.active.payment_sources.includes(:credit_account).order(:kind, :name)
  end

  # Recent incomes, optionally narrowed by description, category or an
  # explicit date range. The cycle summary stays period-based unless the user
  # picks dates, so filtering the table never changes its totals silently.
  def filtered_incomes
    @filtered_incomes ||= begin
      if @filter_errors.any?
        Income.none
      else
        scope = Income.for_user(current_user).includes(:category, money_source: :credit_account)
        # The header and summary already follow the financial cycle; the table
        # must not mix in incomes from the previous one. Explicit dates win, so
        # users can review another cycle without changing their schedule.
        scope = scope.where(date: @cycle_filter.to_range) if @cycle_filter
        scope = scope.where("date >= ?", start_date) if start_date
        scope = scope.where("date <= ?", end_date) if end_date

        if (query = params[:q].to_s.strip).present?
          scope = scope.where("description ILIKE ?", "%#{Income.sanitize_sql_like(query)}%")
        end

        scope = scope.where(category_id: params[:category_id]) if params[:category_id].present?
        scope
      end
    end
  end

  def income_summary
    incomes = if @filter_errors.any?
      Income.none
    elsif @cycle_filter
      Income.for_user(current_user).where(date: @cycle_filter.to_range)
    elsif @date_filter_applied
      date_filtered_incomes
    else
      Income.for_user(current_user).where(date: @period.to_range)
    end

    {
      total: incomes.sum(:amount),
      count: incomes.count,
      monthly_incomes: current_user.recurring_templates.income.count
    }
  end

  def date_filtered_incomes
    scope = Income.for_user(current_user)
    scope = scope.where("date >= ?", start_date) if start_date
    scope = scope.where("date <= ?", end_date) if end_date
    scope
  end

  # Explicit dates take precedence over the cycle prefill.
  def cycle_filter
    return nil if @date_filter_applied
    return nil unless Reports::Period.cycles_enabled?(current_user)

    @period
  end

  def start_date
    @start_date ||= parse_date(params[:start_date])
  end

  def end_date
    @end_date ||= parse_date(params[:end_date])
  end

  def parse_date(value)
    return nil if value.blank?

    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end

  def date_filter_errors
    errors = {}
    if params[:start_date].present? && start_date.nil?
      errors[:start_date] = t("incomes.index.errors.valid_from")
    end
    if params[:end_date].present? && end_date.nil?
      errors[:end_date] = t("incomes.index.errors.valid_to")
    end
    if start_date && end_date && start_date > end_date
      errors[:start_date] = t("incomes.index.errors.from_after_to")
    end
    errors
  end

  def income_params
    permitted = [ :amount, :description, :date, :category_id ]
    permitted << :money_source_id if money_tracking_detailed?
    params.require(:income).permit(*permitted)
  end

  # Optional prefill for the standard new-income form, used when it is opened
  # from the Día de Balance reconciliation modal (amount/money source of the
  # difference). Only fills the form; creation still goes through create.
  def assign_income_prefill
    prefill = params.permit(:amount, :description, :money_source_id, :date)
    return if prefill.blank?

    @income.amount = prefill[:amount] if prefill[:amount].present?
    @income.description = prefill[:description] if prefill[:description].present?
    @income.date = prefill[:date] if prefill[:date].present?

    return if prefill[:money_source_id].blank? || !money_tracking_detailed?

    source = current_user.money_sources.find_by(id: prefill[:money_source_id])
    @income.money_source = source if source
  end
end
