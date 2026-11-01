# frozen_string_literal: true

# Loads the associations needed by the money source show page, shared by the
# summary (MoneySourcesController) and extracto (MoneySourceExtractsController)
# entry points so both can render the same tabs.
module MoneySourceShowContext
  extend ActiveSupport::Concern

  private

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
  def load_pocket_context
    @pocket_goals = @money_source.goals.active.order(:created_at, :id).includes(:goal_allocations)
    @recent_allocations = @money_source.goal_allocations
                                       .includes(:financial_goal)
                                       .order(date: :desc, created_at: :desc)
                                       .limit(5)
  end
end
