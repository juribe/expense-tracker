# frozen_string_literal: true

module Ai
  module Tasks
    # Parse one or more expenses from natural-language text in a single AI call.
    #
    #   input:   "Ayer compré mercado por 180 mil en Éxito, después pagué 50 mil de gasolina"
    #   context: { user:, today: Date, categories: [Category, ...] }
    #   data:    [
    #     {
    #       original_text:,
    #       amount:,
    #       date:,
    #       description:,
    #       category:
    #     },
    #     ...
    #   ]
    class ConversationExpenseParsing < Base
      def timeout
        25
      end

      def messages(input, context)
        [
          { role: "system", content: system_prompt(context) },
          { role: "user", content: input.to_s }
        ]
      end

      def parse(content, input, context)
        payload = parse_json(content)
        entries = payload.is_a?(Array) ? payload : payload["expenses"]

        raise InvalidResponse, "missing 'expenses' array" unless entries.is_a?(Array) && entries.any?

        categories = Array(context[:categories])
        today = (context[:today] || Date.current).to_date

        expenses = entries.filter_map do |entry|
          next unless entry.is_a?(Hash)

          score = Expenses::ConfidenceCalculator.call(
            expense: ParsedExpense.build_expense(entry),
            input: input,
            categories: categories,
            today: today
          ).score

          ParsedExpense.build_expense(
            entry.merge("confidence" => score)
          )
        end

        raise InvalidResponse, "no usable expense entries" if expenses.empty?

        {
          data: expenses,
          confidence: expenses.map(&:confidence).min || 0.0
        }
      end

      private

      def system_prompt(context)
        today = (context[:today] || Date.current).to_date.iso8601

        categories = Array(context[:categories]).map do |category|
          category.respond_to?(:name) ? category.name : category.to_s
        end.join(", ")

        hint = context[:context].presence
        context_block = hint ? "\nAdditional context: #{hint}\n" : ""

        <<~PROMPT
          Extract every distinct expense from the user's natural-language message.
          Return each transaction as a separate expense object.

          #{context_block}

          Today: #{today}
          Currency: COP
          Available categories: [#{categories}]

          For each expense return:

          - original_text: the complete portion of the user's original message
            belonging to this expense. Preserve the original words exactly when
            possible. Include all relevant information such as description,
            amount, merchant, date and payment method. Do not summarize, translate,
            rewrite or omit information from this portion of the message.
          - amount: integer amount in COP. Examples: "50 mil" = 50000,
            "50 lucas" = 50000, "50k" = 50000.
          - date: YYYY-MM-DD. Resolve dates mentioned by the user using Today.
            If no date is mentioned, use Today.
            Only use another date when the message clearly indicates that the expense
            happened on a different day.
          - description: short description of the expense in the same language
            used by the user. Do not translate or invent information.
          - category: the most appropriate category from Available categories.
            Only assign a category when there is enough information in the user's
            message to reasonably determine what the expense was for.
            If the purpose of the expense cannot be determined from the message,
            return null.
            Never infer a debt, loan, credit payment, purchase, service, gift,
            food, transportation, or any other purpose solely from the recipient,
            merchant, payment method, or transfer type.

          Rules:

          - Return every distinct transaction.
          - Keep all information belonging to a transaction in its original_text.
          - Separate transactions even when they use the same payment method.
          - Keep multiple items as one expense when they belong to the same purchase.
          - A payment method mentioned once may apply to multiple expenses.
          - Do not create a separate expense for a payment method.
          - Do not invent missing information.
          - Do not create IDs or database entities.
          - original_text must come from the user's message.
          - Return only valid JSON. No markdown or explanations.
          - If the user does not provide a date, assume the expense happened Today.
          - Do not use null for date unless the user explicitly provides an ambiguous
            date that cannot reasonably be resolved.
          - A bank transfer, BRE transfer, or transfer to a person does not indicate
            the purpose of the expense by itself. For example, "BRE a Juan Pérez"
            could be a debt payment, food purchase, service, gift, or something else.
            If the purpose is not stated or strongly supported by the message,
            category must be null.

          Output:

          {
            "expenses": [
              {
                "original_text": "...",
                "amount": 50000,
                "date": "2026-09-16",
                "description": "gasolina",
                "category": "Transporte"
              }
            ]
          }
        PROMPT
      end
    end
  end
end
