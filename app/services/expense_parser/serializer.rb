class ExpenseParser
  class Serializer
    def self.call(expenses)
      expenses.map { |expense| serialize(expense) }
    end

    private

    def self.serialize(expense)
      {
        amount: expense.amount&.to_f,
        description: expense.description,
        transaction_date: expense.transaction_date&.iso8601,
        category_id: expense.category_id,
        category_name: expense.category_name,
        create_category: expense.create_category || false,
        confidence: expense.confidence,
        low_confidence: expense.low_confidence?,
        warnings: Array(expense.warnings),
        money_source_id: expense.money_source_id,
        money_source_name: expense.money_source_name
      }
    end
  end
end
