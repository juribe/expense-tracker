# frozen_string_literal: true

# Loads the associations needed by the money source show page, shared by the
# summary (MoneySourcesController) and extracto (MoneySourceExtractsController)
# entry points so both can render the same tabs.
module MoneySourceShowContext
  extend ActiveSupport::Concern

  private

  # Shared by MoneySource#show, Mi dinero and the statement/extract page.
  def load_statement_context(paginate: true)
    @statement = MoneySources::Statement.new(
      user: current_user,
      source: @money_source,
      period: params[:period],
      start_date: params[:start_date],
      end_date: params[:end_date],
      kind: params[:kind],
      query: params[:q],
      page: params[:page],
      per_page: params[:per_page],
      paginate: paginate
    ).call

    # Simple Mi dinero aggregates every recorded movement, including the ones
    # that still live on sources used before switching from advanced mode.
    if current_user.money_tracking_simple? && @money_source.general?
      @simple_recorded_balance = Transaction.where(user_id: current_user.id).sum(:amount).to_d
    end
  end

  # Applied payments paginate on the debt show page: a long mortgage history
  # must stay one click away without flooding the card.
  def load_payment_context
    payments_scope = @money_source.payments.order(date: :desc, id: :desc)
    # The list renders the expense description/date of every payment.
    @payments = payments_scope.includes(:expense).paginate(
      page: params[:payments_page], per_page: ApplicationController::PER_PAGE
    )

    unapplied = current_user.expenses
                            .where.not(id: @money_source.payments.select(:expense_id))
                            .where.not(source: "gmf")
                            .order(date: :desc, id: :desc)
    # Only the awaiting list renders the template hint; the picker does not,
    # so the eager load stays scoped to what is used (keeps Bullet quiet).
    @awaiting_expenses = unapplied.includes(:recurring_template)
                                  .where(recurring_template_id: current_user.recurring_templates
                                                                           .where(money_source_id: @money_source.id)).limit(10)
    @pickable_expenses = unapplied.limit(20)
    # Data for the "Crear pago manual" modal on the payments tab.
    @categories = Category.for_user(current_user).expenses.order(:name)
    @funding_sources = MoneySource.payment_origins(current_user).where.not(id: @money_source.id)
  end

  # Pockets display how their balance is distributed across their goals.
  # Goal#saved_amount reads the pocket, so it must be eager loaded too.
  def load_pocket_context
    @pocket_goals = @money_source.goals.active.order(:created_at, :id).includes(:goal_allocations, :pocket)
    @recent_allocations = @money_source.goal_allocations
                                       .includes(:financial_goal)
                                       .order(date: :desc, created_at: :desc)
                                       .limit(5)
  end
end
