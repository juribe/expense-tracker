# frozen_string_literal: true

module Gmail
  # Fills the category of an email's transactions. The deterministic resolver
  # runs first and only the unresolved expense entries reach the AI, in ONE
  # batched suggestion call per email. A suggestion is folded back into the
  # user's existing categories; when nothing matches it is kept as review text
  # for the candidate UI. Never creates categories.
  #
  #   prefills = Gmail::CategoryPrefill.new(user: user).call(transactions)
  #   prefills.first.category     # => Category or nil
  #   prefills.first.suggestion   # => "Videojuegos" or nil
  class CategoryPrefill
    Prefill = Struct.new(:category, :suggestion, keyword_init: true)

    def initialize(user:, suggester: nil)
      @user = user
      @suggester = suggester
    end

    def call(transactions)
      transactions = Array(transactions)
      prefills = transactions.map { |transaction| resolve(transaction) }
      fill_suggestions(transactions, prefills)
      prefills
    end

    private

    attr_reader :user

    def resolve(transaction)
      return Prefill.new unless expense?(transaction)

      Prefill.new(category: resolve_name(transaction[:category], transaction[:merchant]))
    end

    def expense?(transaction)
      transaction[:type].to_s == "expense"
    end

    def resolve_name(name, activity)
      Categories::ClosestResolver.call(user: user, name: name, activity: activity).category
    end

    def fill_suggestions(transactions, prefills)
      pending = pending_indexes(transactions, prefills)
      return if pending.empty?

      suggestions = suggest(pending, transactions)
      return if suggestions.blank?

      apply_suggestions(pending, transactions, prefills, suggestions)
    end

    def pending_indexes(transactions, prefills)
      prefills.each_index.select do |index|
        prefills[index].category.nil? && expense?(transactions[index])
      end
    end

    def suggest(pending, transactions)
      items = pending.each_with_index.map do |index, position|
        { "index" => position, "description" => transactions[index][:merchant].to_s }
      end
      result = suggester.call(items)
      result.data if result&.ok?
    end

    def apply_suggestions(pending, transactions, prefills, suggestions)
      pending.each_with_index do |index, position|
        name = suggestions[position.to_s] || suggestions[position]
        next if name.blank?

        category = resolve_name(name, transactions[index][:merchant])
        prefills[index] = Prefill.new(category: category, suggestion: category.nil? ? name : nil)
      end
    end

    def suggester
      @suggester ||= method(:default_suggestion)
    end

    def default_suggestion(items)
      return nil unless Ai.configuration.configured?

      Ai::Router.call(task: :category_suggestion, input: items, context: { user: user })
    end
  end
end
