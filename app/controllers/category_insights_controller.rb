# frozen_string_literal: true

# CategoryInsightsController
# Shows the Category Insight detail view for a subcategory.
class CategoryInsightsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_category, only: [:show]

  def index
    categories = Category.for_user(current_user).expenses.active
    @categories = categories.select { |category| category.suggested_savings_percentage.to_d.positive? }
                            .map do |category|
      insight = CategoryInsight.new(user: current_user, category: category).call
      { category: category, insight: insight, average: insight[:average_spending].to_d }
    end
    @categories.sort_by! { |row| -row[:average] }
  end

  def show
    @insight = CategoryInsight.new(user: current_user, category: @category).call
  end

  private

  def set_category
    id = params[:category_id].presence || params[:id]
    @category = Category.for_user(current_user).find(id)
  rescue ActiveRecord::RecordNotFound
    flash[:alert] = t("category_messages.not_found", default: "Categoría no encontrada")
    redirect_to categories_path
  end
end

CategoryInsightController = CategoryInsightsController unless defined?(CategoryInsightController)
