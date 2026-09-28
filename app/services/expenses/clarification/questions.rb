# frozen_string_literal: true

module Expenses
  module Clarification
    # Builds and delivers the Spanish clarification questions for a session's
    # pending candidates. Candidates are referenced by a stable 1..n numbering
    # (never internal IDs).
    #
    #   - One pending candidate: direct question; money source and category
    #     use an interactive WhatsApp list (tap = deterministic, no LLM).
    #   - Several candidates sharing the same missing field: ONE grouped
    #     question with a numbered bullet list and an ordered-answer hint.
    #   - Several candidates with different missing fields: one concise
    #     grouped question listing what is missing for each.
    module Questions
      FIELD_QUESTIONS = {
        "amount" => "¿Cuánto fue?",
        "date" => "¿De qué fecha fue?",
        "description" => "¿Qué fue?",
        "category_id" => "¿En qué categoría encaja?",
        "money_source_id" => "¿Con qué fuente de dinero se pagó?"
      }.freeze

      FIELD_LABELS = {
        "amount" => "el monto",
        "date" => "la fecha",
        "description" => "qué fue",
        "category_id" => "la categoría",
        "money_source_id" => "el medio de pago"
      }.freeze

      OTHER_ROW = { id: "other", title: "Otra (escribir)" }.freeze

      class << self
        # Ordered missing fields across all pending candidates: a field is
        # listed once, in the first candidate (by index) that misses it.
        def missing_fields(candidates)
          candidates.flat_map { |candidate| candidate.missing_fields }.uniq
        end

        # The candidate's first (lowest-index) missing field.
        def next_field(candidate)
          order = %w[amount date description category_id money_source_id]
          order.find { |field| candidate.missing_fields.include?(field) }
        end

        # Human label for a candidate in questions: description + amount.
        def candidate_label(candidate)
          label = candidate.description.presence || "Gasto"
          label += " — $#{format_amount(candidate.amount)}" if candidate.amount.present?
          label
        end

        # Question text for the session's pending candidates, numbered 1..n in
        # the same order the resolver receives them. A single candidate is
        # asked ONE field at a time (each selectable field gets its own
        # interactive list on its own turn).
        def build_text(pending_candidates)
          if pending_candidates.size == 1
            direct_question(pending_candidates.first)
          else
            grouped_question(pending_candidates)
          end
        end

        # Delivers the question for the session: for a single pending
        # candidate the FIRST missing field is asked, with its interactive
        # list when selectable; multiple candidates get the grouped text.
        # When the interactive list cannot be delivered (Meta API failure,
        # payload rejection) the question still reaches the user as plain
        # text — a clarification never dies in silence.
        # Returns the delivered question text for persistence.
        def deliver(session)
          pending = session.pending_candidates.to_a
          text = build_text(pending)

          delivered = false
          if pending.size == 1
            field = next_field(pending.first)
            delivered = send_source_list(session.phone_number, pending.first, text) if field == "money_source_id"
            delivered = send_category_list(session.phone_number, pending.first, text) if field == "category_id"
          end
          Whatsapp::ReplySender.send_to(session.phone_number, text) unless delivered

          text
        end

        private

        def direct_question(candidate)
          field = next_field(candidate)
          "#{expense_context(candidate)} #{FIELD_QUESTIONS.fetch(field, 'Me falta información.')}"
        end

        def grouped_question(pending_candidates)
          grouped = pending_candidates.group_by { |candidate| candidate.missing_fields.sort }

          if grouped.size == 1
            field_names = grouped.keys.first.map { |field| FIELD_LABELS.fetch(field, field) }.to_sentence
            lines = pending_candidates.each_with_index.map do |candidate, index|
              "#{index + 1}. #{candidate_label(candidate)}"
            end
            example = ordered_example(pending_candidates)
            <<~MSG.strip
              Me faltan #{field_names} de estos gastos:

              #{lines.join("\n")}

              Puedes responder en el mismo orden, por ejemplo: "#{example}"
            MSG
          else
            lines = pending_candidates.each_with_index.map do |candidate, index|
              missing = candidate.missing_fields.map { |field| FIELD_LABELS.fetch(field, field) }.join(" y ")
              "#{index + 1}. #{candidate_label(candidate)}: falta #{missing}"
            end
            "Me faltan algunos datos de estos gastos:\n\n#{lines.join("\n")}\n\n" \
              "Respóndeme con el número o el nombre del gasto y el dato, ej: \"2 gasolina efectivo\""
          end
        end

        def ordered_example(pending_candidates)
          field = pending_candidates.first.missing_fields.first
          if field == "money_source_id"
            "tarjeta, efectivo, tarjeta".split(", ").first(pending_candidates.size).join(", ")
          elsif field == "category_id"
            Array.new(pending_candidates.size, "transporte").join(", ")
          else
            "dato1, dato2, dato3".split(", ").first(pending_candidates.size).join(", ")
          end
        end

        def expense_context(candidate)
          what = candidate.description.presence || "Tu gasto"
          parts = [ "\"#{what}\"" ]
          parts << "de $#{format_amount(candidate.amount)}" if candidate.amount.present?
          parts << "del #{candidate.date.strftime('%d/%m/%Y')}" if candidate.date.present?
          "Registré #{parts.join(' ')}."
        end

        def format_amount(amount)
          ActionController::Base.helpers.number_to_currency(amount, unit: "", delimiter: ".", separator: ",",
                                                            precision: 0)
        end

        def send_source_list(phone_number, candidate, text)
          sources = candidate.user.money_sources.active.order(:kind, :name).to_a
          return false if sources.empty?

          rows = sources.first(9).map { |source| { id: "source:#{source.id}", title: source.display_name } }
          Whatsapp::ReplySender.send_list(phone_number, text, rows + [ OTHER_ROW ])
        end

        def send_category_list(phone_number, candidate, text)
          rows = category_rows(candidate)
          return false if rows.empty?

          Whatsapp::ReplySender.send_list(phone_number, text, rows + [ OTHER_ROW ])
        end

        # The candidate's AI suggestion first (if any), then the user's most
        # frequently used expense categories; with no usage history the
        # available expense categories fill the list.
        def category_rows(candidate)
          user = candidate.user
          rows = []

          suggestion = candidate.category_suggestion.presence
          if suggestion
            suggested = Categories::ClosestResolver.call(user: user, name: suggestion).category
            rows << { id: "category:#{suggested.id}", title: suggested.name } if suggested
          end

          category_ids = user.expenses.where.not(category_id: nil)
                             .group(:category_id)
                             .order(Arel.sql("COUNT(category_id) DESC"))
                             .limit(suggestion ? 8 : 9).pluck(:category_id)
          if category_ids.empty?
            category_ids = Category.for_user(user).expenses.limit(9).pluck(:id)
          end
          categories = Category.expenses.where(id: category_ids).index_by(&:id)
          rows += category_ids.filter_map { |id| { id: "category:#{id}", title: categories[id].name } if categories[id] }

          rows.uniq { |row| row[:id] }
        end
      end
    end
  end
end
