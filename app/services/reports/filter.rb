# frozen_string_literal: true

# Reports::Filter
# Composable report filters (category, money source, card, loan, kind) turned
# into scoped relations shared by every report service.
#
# Associations: none (value object over the user's records)
# Methods: expense_scope, income_scope, transfer_scope, applied_filters
#
# Example: Reports::Filter.new(user: user, period: period, category_id: 7).expense_scope(period.range)
class Reports::Filter
  KINDS = %w[expense income].freeze

  attr_reader :user, :period

  def initialize(user:, period:, category_id: nil, money_source_id: nil,
                 credit_card_id: nil, loan_id: nil, kind: nil)
    @user = user
    @period = period
    @category_id = category_id.presence&.to_i
    @money_source_id = (credit_card_id.presence || loan_id.presence || money_source_id.presence)&.to_i
    @kind = kind.to_s.presence_in(KINDS)
  end

  def expense_scope(range)
    return Expense.none if @kind == "income"

    scoped(Expense.all, range)
  end

  def income_scope(range)
    return Income.none if @kind == "expense"

    scoped(Income.all, range)
  end

  def transfer_scope(range)
    transfers = @user.transfers.where(date: range)
    return transfers if @money_source_id.blank?

    transfers.where("from_source_id = :id OR to_source_id = :id", id: @money_source_id)
  end

  def applied_filters
    chips = []
    chips << "category" if @category_id
    chips << "money_source" if @money_source_id
    chips << "kind" if @kind
    chips
  end

  # The validated money source id (nil when unset or unknown), public because
  # debt reports scope per-source groups with it.
  def active_source_id
    valid_source_id if @money_source_id
  end

  private

  # Unknown ids are dropped silently: a stale filter must never blank out a
  # report page with an error.
  def scoped(transactions, range)
    scope = transactions.for_user(@user).where(date: range)
    category_id = valid_category_id
    source_id = valid_source_id
    scope = scope.where(category_id: category_id) if category_id
    scope = scope.where(money_source_id: source_id) if source_id
    scope
  end

  def valid_category_id
    @valid_category_id ||= Category.for_user(@user).exists?(@category_id) ? @category_id : nil
  end

  def valid_source_id
    @valid_source_id ||= @user.money_sources.exists?(@money_source_id) ? @money_source_id : nil
  end
end
