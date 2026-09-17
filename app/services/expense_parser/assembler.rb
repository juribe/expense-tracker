class ExpenseParser
  class Assembler
    def initialize(text:, user:, categories:, notes:, money_source_detector: nil)
      @text = text.to_s.strip
      @user = user
      @categories = categories
      @notes = notes
      @money_source_detector = money_source_detector || MoneySources::Detector.new(user: user)
    end

    def build(entry)
      expense = build_expense(entry)
      assign_money_source(expense)
      apply_matching_rule_category(expense)
      if expense.valid?
        expense
      else
        @notes.concat(expense.errors.map { |message| "#{expense.description}: #{message}" })
        nil
      end
    end

    private

    # ==========================================================================
    # 7. ASSEMBLY — entries → ParsedExpense, enriched and validated
    # ==========================================================================
    def build_expense(entry)
      return entry if entry.is_a?(ParsedExpense)

      ParsedExpense.new(
        amount: to_numeric(entry[:amount]),
        description: entry[:description].presence&.to_s&.strip,
        transaction_date: entry[:transaction_date].is_a?(Date) ? entry[:transaction_date] : ExpenseParser::DateService.parse_iso_date(entry[:transaction_date]),
        category_id: resolve_existing_category_id(entry),
        category_name: entry[:category_name].presence,
        create_category: entry[:create_category],
        confidence: to_float(entry[:confidence]),
        warnings: Array(entry[:warnings]),
        source_hint: entry[:source_hint]
      )
    end

    def resolve_existing_category_id(entry)
      return nil if entry[:create_category]

      name = ExpenseParser::TextService.normalize_text(entry[:category_name].to_s)
      return nil if name.blank?

      exact = @categories.find { |category| ExpenseParser::TextService.normalize_text(category.name) == name }
      return exact.id if exact

      partial = @categories.find { |category| ExpenseParser::TextService.normalize_text(category.name).include?(name) || name.include?(ExpenseParser::TextService.normalize_text(category.name)) }
      partial&.id
    end

    # A single mention of an account in the message usually applies to every
    # detected expense (e.g. "gasté 50 mil en almuerzo y 20 mil en parqueadero
    # desde nequi"). If a specific source was already attached, leave it alone.
    def assign_money_source(expense)
      return if expense.money_source_id.present?

      source = @money_source_detector.call(@text)
      return unless source

      expense.money_source_id = source.id
      expense.money_source_name = source.name
    end

    # The preview must reflect what will actually be saved: when a transaction
    # rule matches the detected expense, its category replaces the parser's
    # suggestion, so no "new category will be created" warning is shown.
    def apply_matching_rule_category(expense)
      probe = Expense.new(user: @user, description: expense.description.presence,
                          amount: expense.amount, money_source_id: expense.money_source_id)
      rule = TransactionRules::Applicator.new(@user).matching_category_rule(probe)
      return if rule.nil?

      expense.category_id = rule.category_id
      expense.category_name = rule.category.name
      expense.create_category = false
      expense.warnings = expense.warnings.grep_v(/\A(?:No matching category found|We could not determine a category)/)
    end

    def to_numeric(value)
      return value if value.is_a?(Numeric)
      return nil if value.blank?

      value.to_s.delete("$ .,").to_d
    rescue ArgumentError, TypeError
      nil
    end

    def to_float(value)
      return nil if value.blank?
      return value if value.is_a?(Numeric)

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end
