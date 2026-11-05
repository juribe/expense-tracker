# frozen_string_literal: true

module SavingsOpportunities
  # SavingsOpportunities::ConfiguredRecurring
  # Builds recurring payment rows from the user's configured recurring
  # templates. It is the fallback used when there is no previous-cycle
  # spending to detect patterns from: these are planned payments, not
  # payments confirmed by observed movements, so they are marked as
  # configured instead of confirmed.
  #
  # Methods: call
  #
  # Example: SavingsOpportunities::ConfiguredRecurring.new(user:).call[:rows]
  class ConfiguredRecurring
    MOVEMENTS_LIMIT = 5
    MONTHLY_FACTORS = Reports::Recurring::MONTHLY_FACTORS

    attr_reader :user

    def initialize(user:)
      @user = user
    end

    def call
      rows = templates.filter_map { |template| build_row(template) }
                      .sort_by { |row| -row[:monthly_amount] }

      {
        source: "configured",
        rows: rows,
        total_monthly: rows.sum(0.to_d) { |row| row[:monthly_amount] },
        confirmed_count: 0,
        possible_count: rows.size
      }
    end

    private

    def templates
      @templates ||= RecurringTemplate.for_user(user)
                                      .active
                                      .expense
                                      .includes(:category, :transactions)
                                      .ordered
                                      .to_a
    end

    def build_row(template)
      return nil if template.amount.to_d <= 0

      category = template.category
      transactions = template.transactions.sort_by { |transaction| [ transaction.date, transaction.created_at ] }.reverse

      {
        key: "template-#{template.id}",
        template_id: template.id,
        name: template.description.presence || category.name,
        amount: template.amount.to_d,
        frequency: template.frequency.to_s,
        monthly_amount: (template.amount.to_d * factor(template.frequency)).round(2),
        last_date: transactions.first&.date,
        payment_day: template.payment_day,
        occurrences: transactions.size,
        confidence: :configured,
        movements: movements(transactions, category)
      }
    end

    def factor(frequency)
      MONTHLY_FACTORS.fetch(frequency.to_s, 1.to_d)
    end

    def movements(transactions, category)
      transactions.first(MOVEMENTS_LIMIT).map do |transaction|
        {
          id: transaction.id,
          date: transaction.date,
          amount: transaction.amount.to_d.abs,
          description: transaction.description,
          category_name: category.name
        }
      end
    end
  end
end
