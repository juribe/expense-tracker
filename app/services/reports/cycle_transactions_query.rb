# frozen_string_literal: true

# Reports::CycleTransactionsQuery
# Filtered movements that compose a cycle balance: valid incomes plus real
# expenses (expenses already applied to a debt are excluded, exactly like the
# cycle totals). Type, category and description filters combine and always stay
# inside the authenticated user's records.
#
# Methods: call
#
# Example: Reports::CycleTransactionsQuery.new(user:, range:, type: "expense", query: "DiDi").call
class Reports::CycleTransactionsQuery
  TYPES = %w[all expense income].freeze

  def initialize(user:, range:, type: nil, category_id: nil, query: nil)
    @user = user
    @range = range
    @type = TYPES.include?(type.to_s) ? type.to_s : "all"
    @category_id = category_id
    @query = query.to_s.strip
  end

  def call
    scope = Transaction.for_user(user)
                       .where(date: range)
                       .where.missing(:payments)
                       .includes(:category)
                       .order(date: :desc, created_at: :desc)

    scope = scope.where(kind: type) unless type == "all"
    scope = scope.where(category_id: category_id) if valid_category_id
    scope = scope.where("transactions.description ILIKE ?", "%#{search_term}%") if search_term.present?
    scope
  end

  private

  attr_reader :user, :range, :type, :query

  def category_id
    @category_id
  end

  def valid_category_id
    return @valid_category_id if defined?(@valid_category_id)

    @valid_category_id = category_id.present? && Category.for_user(user).exists?(category_id)
  end

  def search_term
    @search_term ||= ActiveRecord::Base.sanitize_sql_like(query)
  end
end
