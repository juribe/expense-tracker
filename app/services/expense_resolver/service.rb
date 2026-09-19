module ExpenseResolver
 class Service
    attr_accessor :text, :user, :expenses, :context, :execution

    def initialize(text:, user:, context: nil, execution: nil)
      @text = text
      @user = user
      @expenses = []
      @context = context
      @execution = execution
    end

    def self.call(text:, user:, context: nil, execution: nil)
      new(text: text, user: user, context: context, execution: execution).process
    end

    def process
       # steps
       # basic validations
       return ServiceResult.error("missing text") if invalid_text?
       return ServiceResult.error("missing user") if invalid_user?

       # IA checks expenses
       parser_result = NaturalLanguageParser.call(text: text, user: user, categories: categories_names)
       return parser_result if parser_result.failure?

       parser_result.result.each do |expense|
         expenses << CandidateDetector.call(expense: expense,
                                            user: user,
                                            categories: categories,
                                            money_source_detector: money_source_detector
                                          )
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

    def money_source_detector
      @money_source_detector ||= MoneySources::Detector.new(user: user)
    end
 end
end
