# frozen_string_literal: true

module Expenses
  # Query object for the expenses index: validates the filter form, applies
  # filters/sort, and paginates in one place so any consumer (HTML list, CSV
  # export, future JSON) shares identical semantics.
  #
  #   result = Expenses::Search.call(user: user, params: params)
  #   result.success?       # false when filter validation fails
  #   result.relation       # paginated will_paginate collection
  #   result.csv_scope      # same filters/sort, without limit/offset
  #   result.total_count    # count of the fully filtered set
  #   result.filtered_total # amount sum over the fully filtered set
  #   result.page_subtotal  # sum of the current page only
  #   result.sort / result.dir       # sanitized sort column/direction
  #   result.filter_errors  # {} or { field => "message" }
  class Search
    SORTABLE_COLUMNS = %w[date description category amount].freeze
    SORT_DIRECTIONS = %w[asc desc].freeze
    DEFAULT_SORT_DIR = { "date" => "desc", "amount" => "desc" }.freeze

    attr_reader :relation, :csv_scope, :total_count, :filtered_total,
                :sort, :dir, :filter_errors

    def self.call(user:, params:, period_range: nil)
      new(user: user, params: params, period_range: period_range)
    end

    def initialize(user:, params:, period_range: nil)
      @user = user
      @params = params
      @period_range = period_range
      run
    end

    def success?
      filter_errors.empty?
    end

    def failure?
      !success?
    end

    def page_subtotal
      @relation.sum(&:amount)
    end

    private

    attr_reader :user, :params

    def run
      @sort = sanitized_sort
      @dir = sanitized_dir
      @filter_errors = validate_filters

      if filter_errors.any?
        @relation = Expense.none
        @csv_scope = user.expenses.none
        @total_count = 0
        @filtered_total = 0
        return
      end

      scope = user.expenses.includes(:category, { money_source: :credit_account })
      scope = apply_filters(scope)
      scope = apply_sort(scope)
      @csv_scope = scope
      @total_count = scope.count
      @filtered_total = scope.sum(:amount)
      @relation = scope.paginate(page: params[:page], per_page: ApplicationController::PER_PAGE)
    end

    def sanitized_sort
      value = params[:sort].to_s
      SORTABLE_COLUMNS.include?(value) ? value : "date"
    end

    def sanitized_dir
      value = params[:dir].to_s
      SORT_DIRECTIONS.include?(value) ? value : "desc"
    end

    def validate_filters
      errors = {}
      if params[:start_date].present? && params[:end_date].present?
        if !valid_date?(params[:start_date])
          errors[:start_date] = I18n.t("expenses.error_valid_from")
        elsif !valid_date?(params[:end_date])
          errors[:end_date] = I18n.t("expenses.error_valid_to")
        elsif params[:start_date] > params[:end_date]
          errors[:start_date] = I18n.t("expenses.error_from_after_to")
        end
      elsif params[:start_date].present? && !valid_date?(params[:start_date])
        errors[:start_date] = I18n.t("expenses.error_valid_from")
      elsif params[:end_date].present? && !valid_date?(params[:end_date])
        errors[:end_date] = I18n.t("expenses.error_valid_to")
      end

      if params[:min_amount].present? && params[:max_amount].present? &&
         money_value(params[:min_amount]) > money_value(params[:max_amount])
        errors[:min_amount] = I18n.t("expenses.error_min_exceeds_max")
      end
      errors
    end

    def valid_date?(value)
      Date.iso8601(value.to_s)
      true
    rescue ArgumentError
      false
    end

    def money_value(value)
      return nil if value.blank?

      BigDecimal(value.to_s.delete(","))
    rescue ArgumentError, TypeError
      nil
    end

    def apply_filters(scope)
      scope = scope.where(date: @period_range) if @period_range
      scope = scope.where("transactions.description ILIKE ?", "%#{like_term}%") if text_search.present?
      scope = scope.in_category(params[:category_id]) if params[:category_id].present?
      scope = scope.where("date >= ?", params[:start_date]) if params[:start_date].present?
      scope = scope.where("date <= ?", params[:end_date]) if params[:end_date].present?
      scope = scope.where("ABS(amount) >= ?", money_value(params[:min_amount])) if params[:min_amount].present?
      scope = scope.where("ABS(amount) <= ?", money_value(params[:max_amount])) if params[:max_amount].present?
      scope = scope.where(money_source_id: params[:money_source_id]) if params[:money_source_id].present?
      scope
    end

    # Free-text search over the description. Surrounding whitespace is
    # ignored and LIKE wildcards are escaped so a literal "%" or "_" typed by
    # the user matches itself instead of widening the query.
    def text_search
      params[:q].to_s.strip
    end

    def like_term
      text_search.gsub(/[\\%_]/) { |char| "\\#{char}" }
    end

    def apply_sort(scope)
      # Append stable secondary keys (created_at, id) so rows sharing the same
      # primary sort value paginate deterministically across databases. The
      # order is expressed with Arel attribute nodes rather than interpolated
      # SQL, so the already-whitelisted column/direction is never concatenated
      # into a query string.
      scope = scope.left_joins(:category) if sort == "category"
      scope.order(*order_nodes)
    end

    def order_nodes
      direction = dir == "asc" ? :asc : :desc

      [ primary_order.public_send(direction),
        Expense.arel_table[:created_at].public_send(direction),
        Expense.arel_table[:id].public_send(direction) ]
    end

    def primary_order
      case sort
      when "category" then Category.arel_table[:name]
      when "amount" then Arel::Nodes::NamedFunction.new("ABS", [ Expense.arel_table[:amount] ])
      else Expense.arel_table[sort]
      end
    end
  end
end
