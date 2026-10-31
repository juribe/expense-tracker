# frozen_string_literal: true

module Mcp
  module Tools
    module Context
      # GetFinancialContextTool
      # Single call that gives an agent the identifiers and figures needed to
      # build structured arguments. No transaction histories are returned.
      class GetFinancialContextTool < Mcp::ApplicationTool
        tool_name "get_financial_context"
        description "Return the user's financial profile, categories, sources, debts, pockets, budgets and goals. Use it before building identifiers."
        requires_scope :read

        SECTIONS = %w[
          profile categories money_sources accounts credit_cards debts
          pockets budgets savings_goals
        ].freeze
        CURRENCY = "COP"
        ACCOUNT_KINDS = %w[account debit_card cash wallet].freeze

        arguments do
          optional(:sections)
            .description "Optional subset: profile, categories, money_sources, accounts, credit_cards, debts, pockets, budgets, savings_goals."
        end

        def call(sections: nil)
          requested = normalize_sections(sections)
          unknown = requested - SECTIONS
          raise Mcp::Error.new("INVALID_ARGUMENT", "Unknown sections: #{unknown.join(', ')}.") if unknown.any?

          success(build_context(requested))
        end

        private

        def normalize_sections(value)
          list = value.is_a?(String) ? value.split(",") : Array(value)
          list.map { |section| section.to_s.strip }.reject(&:blank?).presence || SECTIONS
        end

        def build_context(requested)
          data = { profile: profile }
          data[:categories] = categories if requested.include?("categories")
          data[:money_sources] = money_sources if requested.include?("money_sources")
          data[:accounts] = accounts if requested.include?("accounts")
          data[:credit_cards] = credit_cards if requested.include?("credit_cards")
          data[:debts] = debts if requested.include?("debts")
          data[:pockets] = pockets if requested.include?("pockets")
          data[:budgets] = budgets if requested.include?("budgets")
          data[:savings_goals] = savings_goals if requested.include?("savings_goals")
          data
        end

        def profile
          {
            current_date: Date.current.iso8601,
            timezone: Time.zone.tzinfo.name,
            currency: CURRENCY,
            financial_cycle_start_day: user.financial_cycle_start_day,
            financial_cycles_enabled: user.financial_cycles_enabled?
          }
        end

        def categories
          Category.for_user(user).active.order(:category_type, :name)
                  .map { |category| Mcp::Presenters::CategoryPresenter.new(category).as_json }
        end

        def money_sources
          user.money_sources.active.includes(:credit_account).order(:kind, :name)
              .map { |source| Mcp::Presenters::MoneySourcePresenter.new(source).as_json }
        end

        def accounts
          user.money_sources.active.where(kind: ACCOUNT_KINDS).order(:kind, :name)
              .map do |source|
            {
              id: source.id,
              name: source.name,
              kind: source.kind,
              balance: Mcp::Presenters::Money.money(source.balance),
              parent_id: source.parent_id
            }
          end
        end

        def credit_cards
          user.money_sources.active.where(kind: "credit_card").includes(:credit_account).order(:name)
              .map { |source| Mcp::Presenters::CreditCardPresenter.new(source).as_json }
        end

        def debts
          user.money_sources.active.where(kind: %w[credit_card loan]).includes(:credit_account).order(:kind, :name)
              .map { |source| Mcp::Presenters::DebtPresenter.new(source).as_json }
        end

        def pockets
          user.money_sources.active.pockets.includes(:goal_allocations).order(:name)
              .map { |source| Mcp::Presenters::PocketPresenter.new(source).as_json }
        end

        def budgets
          range = date_range
          user.budgets.active.includes(:category).order(:created_at)
              .map { |budget| Mcp::Presenters::BudgetPresenter.new(budget, range).as_json }
        end

        def savings_goals
          user.goals.active.includes(:pocket, :goal_allocations).order(:created_at)
              .map { |goal| Mcp::Presenters::GoalPresenter.new(goal).as_json }
        end
      end
    end
  end
end
