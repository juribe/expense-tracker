class ExpenseProcessor
    attr_accessor :text, :user, :expenses

    def initialize(text:, user:)
        @text = text
        @user = user
        @expenses = []
    end

    def self.call(text:, user:)
        new(text: text, user: user).process
    end

    def process
       # steps
       # basic validations
       return ServiceResult.error("missing text") if invalid_text?
       return ServiceResult.error("missing user") if invalid_user?

       # IA checks expenses
       parser_result = NaturalLanguageExpenseParser.call(text: text, user: user, categories: categories_names)
       return parser_result if parser_result.failure?

       parser_result.result.each do |expense|
         expenses << ExpenseCandidateProcessor.call(expense: expense, user: user)
       end
       # If all checks pass, return a success result
       ServiceResult.success(expenses)
    end

    def invalid_text?
        text.nil? || text.strip.empty?
    end

    def invalid_user?
        user.nil?
    end

    def categories_names
      @categories_names ||= categories.map(&:name)
    end

    def categories
        @categories ||= Category.for_user(user)
                                .expenses
                                .order(:name)
                                .to_a
    end
end
