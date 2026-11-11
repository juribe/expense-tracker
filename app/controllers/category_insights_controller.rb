# frozen_string_literal: true

# CategoryInsightsController
# Lists categories with savings opportunities and renders each category analysis.
class CategoryInsightsController < ApplicationController
  POTENTIAL_RANK = { "high" => 0, "medium" => 1, "low" => 2 }.freeze

  require_premium

  before_action :authenticate_user!
  before_action :set_category, only: [ :show ]

  def index
    categories = Category.for_user(current_user).expenses.active
    @categories = categories.select { |category| category.suggested_savings_percentage.to_d.positive? }
                            .map do |category|
      insight = CategoryInsight.new(user: current_user, category: category).call
      { category: category, insight: insight, average: insight[:average_spending].to_d,
        current_cycle: insight[:current_cycle_spending].to_d,
        potential: category.savings_potential_level }
    end
    @categories.sort_by! do |row|
      [ POTENTIAL_RANK.fetch(row[:potential], POTENTIAL_RANK["low"]), -row[:current_cycle], row[:category].name ]
    end
    @analyzed_count = @categories.size
    @potential_count = @categories.count { |row| row[:potential] != "low" }
    @limited_history_count = @categories.count { |row| row[:average].zero? }
    @potential_counts = @categories.group_by { |row| row[:potential] }.transform_values(&:size)
  end

  def show
    @insight = CategoryInsight.new(user: current_user, category: @category).call
    @cycle = PayCycle.current(current_user)
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
