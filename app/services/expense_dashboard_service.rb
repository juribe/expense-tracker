# app/services/expense_dashboard_service.rb
require 'active_support/all'

class ExpenseDashboardService
  # Optional scope can include :user, :start_date, :end_date
  # Example: ExpenseDashboardService.new(user: current_user, start_date: 1.month.ago, end_date: Date.today)
  def initialize(scope = {})
    @user      = scope[:user]
    @start_date = scope[:start_date]
    @end_date   = scope[:end_date]

    validate!
  end

  # Returns expenses ordered by created_at descending
  def expenses
    query = Expense.all

    query = query.where(user_id: @user.id) if @user
    query = query.where('created_at >= ?', @start_date) if @start_date
    query = query.where('created_at <= ?', @end_date)   if @end_date

    query.order(created_at: :desc)
  end

  # Returns the sum of all expense amounts within the scope
  def total_spent
    expenses.sum(:amount)
  end

  # Returns a hash mapping category names to summed amounts
  def categories_breakdown
    expenses.group(:category).sum(:amount)
  end

  private

  # Validates the provided scope and raises ArgumentError with a descriptive message
  def validate!
    if @user && !@user.is_a?(User)
      raise ArgumentError, "Invalid user: expected a User instance"
    end

    if @start_date && !@start_date.is_a?(ActiveSupport::TimeWithZone) && !@start_date.is_a?(Date)
      raise ArgumentError, "Invalid start_date: must be a Date or Time"
    end

    if @end_date && !@end_date.is_a?(ActiveSupport::TimeWithZone) && !@end_date.is_a?(Date)
      raise ArgumentError, "Invalid end_date: must be a Date or Time"
    end

    if @start_date && @end_date && @start_date > @end_date
      raise ArgumentError, "Invalid date range: start_date cannot be after end_date"
    end
  end
end