module ExpenseResolver
  class Service
    attr_accessor :text, :user, :expenses, :context, :recording
    attr_reader :engine

    def initialize(text:, user:, context: nil, recording: nil)
      @text = text
      @user = user
      @expenses = []
      @context = context
      @recording = recording
    end

    def self.call(text:, user:, context: nil, recording: nil)
      new(text: text, user: user, context: context, recording: recording).process
    end

    def process
      # basic validations
      return ServiceResult.error("missing text") if invalid_text?
      return ServiceResult.error("missing user") if invalid_user?

      resolution = nil
      unless force_ai?
        resolution = HeuristicResolver.call(text: text, user: user, categories: categories, recording: recording)
      end

      if resolution.nil? || !resolution.resolved?
        # IA checks expenses
        parser_result = NaturalLanguageParser.call(text: text, user: user, categories: categories_names, context: context, recording: recording)
        return parser_result if parser_result.failure?

        entries = parser_result.result
        self.engine = "ai"
      else
        entries = resolution.entries
        self.engine = "heuristic"
      end

      entries.each do |expense|
        expenses << CandidateDetector.call(expense: expense,
                                           user: user,
                                           categories: categories,
                                           money_source_detector: money_source_detector,
                                           classification_source: classification_source,
                                           text: text,
                                           recording: recording,
                                           allow_text_heuristics: entries.size == 1
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

    private

    attr_writer :engine

    def classification_source
      engine == "heuristic" ? "heuristic" : "ai"
    end

    # An evaluation run carries a force_ai execution: the deterministic pass is
    # skipped so the measured model exercises every dataset row.
    def force_ai?
      recording&.execution&.force_ai? || false
    end
  end
end
