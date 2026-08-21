# frozen_string_literal: true

class MonthlyReportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_monthly_report, only: [:show]

  def index
    income_rows = current_user.incomes
      .select("strftime('%Y-%m', date) as month, SUM(amount) as income_total, COUNT(*) as income_count")
      .group("strftime('%Y-%m', date)")
      .index_by(&:month)

    expense_rows = current_user.expenses
      .select("strftime('%Y-%m', date) as month, SUM(amount) as expense_total, COUNT(*) as expense_count")
      .group("strftime('%Y-%m', date)")
      .index_by(&:month)

    months = (income_rows.keys + expense_rows.keys).uniq.sort.reverse

    @monthly_summary = months.map do |month|
      income_row = income_rows[month]
      expense_row = expense_rows[month]
      income_total = income_row&.income_total.to_d
      expense_total = expense_row&.expense_total.to_d

      {
        month: month,
        income_total: income_total,
        expense_total: expense_total,
        net_total: income_total + expense_total,
        count: income_row&.income_count.to_i + expense_row&.expense_count.to_i
      }
    end
  end

  def show
    @incomes = current_user.incomes
      .where("strftime('%Y-%m', date) = ?", @month)
      .order(date: :desc)

    @expenses = current_user.expenses
      .where("strftime('%Y-%m', date) = ?", @month)
      .order(date: :desc)

    @transactions = (@incomes.to_a + @expenses.to_a).sort_by { |record| [record.date, record.created_at || Time.at(0)] }.reverse
    @income_total = @incomes.sum(:amount)
    @expense_total = @expenses.sum(:amount)
    @net_total = @income_total + @expense_total
  end

  private

  def set_monthly_report
    @month = params[:id]
  end
end
