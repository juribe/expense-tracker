# frozen_string_literal: true

module SavingsOpportunities
  # SavingsOpportunities::Analysis
  # Orquestador determinista de la sección: ventana de fechas, categorías,
  # pagos recurrentes, pequeños gastos y simulador. Todos los importes se
  # calculan aquí; la IA solo interpreta este resultado.
  #
  # Methods: call
  #
  # Example: SavingsOpportunities::Analysis.new(user: user).call[:totals]
  class Analysis
    attr_reader :user, :window

    def initialize(user:, date: Date.current)
      @user = user
      @window = Window.new(user: user, date: date)
    end

    def call
      categories = CategoryAnalysis.new(user: user, window: window).call
      recurring = recurring_for(categories)
      small_expenses = SmallExpenses.new(user: user, window: window).call
      simulator = Simulator.new(window: window, categories: categories[:all_rows]).call
      categories_count = categories[:opportunities].size

      {
        user_id: user.id,
        state: state_for(categories),
        generated_at: Time.current.iso8601,
        fingerprint: fingerprint,
        window_label: window.label,
        categories: categories,
        recurring: recurring,
        small_expenses: small_expenses,
        simulator: simulator,
        totals: {
          potential_monthly: categories[:opportunities].sum(0.to_d) { |row| row[:potential] },
          opportunities_count: categories_count + recurring[:rows].size + small_expenses[:groups].size,
          categories_count: categories_count,
          recurring_count: recurring[:rows].size,
          configured_recurring_count: recurring[:source] == "configured" ? recurring[:rows].size : 0,
          small_expenses_count: small_expenses[:groups].size
        }
      }
    end

    private

    # Without a complete previous cycle there is nothing to compare observed
    # patterns against. When no observed pattern has enough evidence, the
    # user's configured recurring payments are useful to review, clearly marked
    # as configured rather than detected. Observed patterns keep precedence
    # when they exist, and configured templates are never mixed in once there
    # is history.
    def recurring_for(categories)
      detected = RecurringDetection.new(user: user, window: window).call
      return detected if categories[:comparison_available] || detected[:rows].any?

      configured = ConfiguredRecurring.new(user: user).call
      configured[:rows].any? ? configured : detected
    end

    def state_for(categories)
      return :empty if observed_expenses.zero?
      return :insufficient_history unless categories[:comparison_available]

      :ok
    end

    def observed_expenses
      @observed_expenses ||= Expense.for_user(user)
                                    .where(date: observed_range)
                                    .where.missing(:payments)
                                    .where(gmf_origin_type: nil)
                                    .count
    end

    def observed_range
      window.complete_ranges.first.begin..window.current_range.end
    end

    # Changes when movements or configured recurring payments change (or a day
    # passes), so the cached narrative is reused only while its underlying
    # data is still the same.
    def fingerprint
      expense_latest = Expense.for_user(user).maximum(:updated_at)&.to_f
      template_latest = RecurringTemplate.for_user(user).maximum(:updated_at)&.to_f
      Digest::SHA256.hexdigest(
        [ user.id, observed_expenses, expense_latest, template_latest, Date.current ].join(":")
      )
    end
  end
end
