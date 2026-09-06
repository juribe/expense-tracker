# BudgetsController
# RESTful for Budget, plus `?month=YYYY-MM` month navigation on index.
# Requires a signed-in user; budgets are always scoped to current_user.
class BudgetsController < ApplicationController
  before_action :set_budget, only: [ :edit, :update, :destroy ]
  before_action :set_form_categories, only: [ :new, :create, :edit, :update ]

  # GET /budgets
  def index
    @month = resolve_month
    @budgets = current_user.budgets.includes(:category)
  end

  # GET /budgets/new
  def new
    @budget = Budget.new
  end

  # GET /budgets/1/edit
  def edit
  end

  # POST /budgets
  def create
    @budget = current_user.budgets.new(budget_params)

    if @budget.save
      redirect_to budgets_path, notice: t("budgets.flashes.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /budgets/1
  def update
    if @budget.update(budget_params)
      redirect_to budgets_path, notice: t("budgets.flashes.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # DELETE /budgets/1
  def destroy
    @budget.destroy
    redirect_to budgets_path, notice: t("budgets.flashes.destroyed")
  end

  private

  def set_budget
    @budget = current_user.budgets.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = t("budgets.not_found")
    redirect_to budgets_path
  end

  def set_form_categories
    @categories = Category.for_user_and_type(current_user, "expense")
    @categories = @categories.where.not(id: current_user.budgets.where.not(id: @budget&.id).select(:category_id))
  end

  def resolve_month
    month = params[:month]
    return Time.zone.today if month.blank?

    Date.strptime(month, "%Y-%m")
  rescue ArgumentError, TypeError
    flash.now[:alert] = t("budgets.invalid_month")
    Time.zone.today
  end

  def budget_params
    params.require(:budget).permit(:category_id, :monthly_amount, :period, :active)
  end
end
