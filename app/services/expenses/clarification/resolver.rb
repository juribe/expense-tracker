# frozen_string_literal: true

module Expenses
  module Clarification
    # Drives the conversational clarification flow for the incomplete expense
    # candidates of a WhatsApp message. The flow is ARRAY-based end to end:
    # a session groups every incomplete candidate of the original message,
    # questions are grouped (never one message per expense) and the LLM
    # resolver returns one resolution entry per matched candidate.
    #
    #   start_session! — persists the session grouping the candidates and
    #                    delivers the first (grouped) question
    #   handle_reply   — interprets a free-text answer (LLM, array in/out)
    #   handle_tap     — resolves a deterministic interactive list tap (no
    #                    LLM; only when a single candidate is pending)
    #
    # Only missing fields are ever applied; existing candidate data is
    # preserved. Each candidate that becomes complete is converted with the
    # existing ExpenseCandidate#confirm! immediately (no waiting for the
    # rest, no duplicated creation logic). Follow-ups are capped to avoid
    # infinite loops; past the cap the session is abandoned and remaining
    # candidates stay needs_review.
    module Resolver
      module_function

      # Creates the pending session for the incomplete candidates (when none
      # exists) and delivers the first grouped question. Returns the session
      # or nil when nothing is missing or a session is already open.
      def start_session!(user:, phone_number:, candidates:, original_message: nil)
        incomplete = candidates.select { |candidate| candidate.missing_fields.present? }
        return nil if incomplete.empty?
        return nil if user.expense_clarifications.pending.exists?

        session = user.expense_clarifications.create!(
          phone_number: phone_number,
          original_message: original_message
        )
        incomplete.each do |candidate|
          session.expense_clarification_candidates.create!(
            expense_candidate: candidate,
            missing_fields: candidate.missing_fields
          )
        end
        session.update!(question: Questions.deliver(session), questions_count: 1)
        session
      end

      # Free-text answer to the pending clarification. Returns
      # [outcome_symbol, new_expense_fragment] where the fragment is the
      # exact text of a brand-new expense detected in the reply (nil when the
      # reply was purely a clarification). The caller runs the fragment
      # through the normal pipeline; the session stays pending meanwhile.
      def handle_reply(clarification:, reply_text:)
        clarification.with_lock do
          return [ :stale, nil ] unless clarification.pending?
          return [ :stale, nil ] if clarification.all_candidates_resolved?

          result = Ai::Router.call(
            task: :clarification_resolution,
            input: reply_text,
            context: {
              user: clarification.user,
              candidates: candidates_context(clarification),
              question: clarification.question,
              original_message: clarification.original_message,
              categories: Category.for_user(clarification.user).expenses.pluck(:name),
              money_source_identifiers: money_source_identifiers(clarification.user),
              today: Date.current
            }
          )

          unless result.ok?
            Whatsapp::ReplySender.send_to(clarification.phone_number,
                                          "No pude procesar tu respuesta, inténtalo de nuevo 🙏")
            return [ :llm_error, nil ]
          end

          data = result.data
          new_expense_text = data[:new_expense_text].presence
          applied = apply_resolutions!(clarification, data[:resolutions] || [])

          if clarification.all_candidates_resolved?
            complete_session!(clarification)
            outcome = :completed
          elsif applied.positive?
            outcome = follow_up(clarification)
          elsif new_expense_text.blank?
            outcome = follow_up(clarification, "No entendí cuál gasto estás aclarando. " +
                                              Questions.build_text(clarification.pending_candidates))
          end

          [ outcome, new_expense_text ]
        end
      rescue StandardError => e
        Rails.logger.error("[Clarification::Resolver] reply failed: #{e.message}")
        Whatsapp::ReplySender.send_to(clarification.phone_number,
                                      "Tuve un problema procesando tu respuesta, inténtalo de nuevo 🙏")
        [ :error, nil ]
      end

      # Deterministic resolution of a tapped list row: "source:<id>",
      # "category:<id>" or "other" (asks the user to write it instead; this
      # navigation does not count against the follow-up limit). Only offered
      # while a single candidate is pending.
      def handle_tap(clarification:, interactive_reply:)
        clarification.with_lock do
          return :stale unless clarification.pending?

          pending = clarification.pending_candidates.to_a
          return :stale if pending.empty?

          candidate = pending.first
          row_id = interactive_reply["id"].to_s

          case row_id
          when /\Asource:(\d+)\z/
            source = clarification.user.money_sources.active.find_by(id: ::Regexp.last_match(1))
            return :tap_ignored unless source

            candidate.update!(money_source_id: source.id)
          when /\Acategory:(\d+)\z/
            category = Category.for_user(clarification.user).expenses.find_by(id: ::Regexp.last_match(1))
            return :tap_ignored unless category

            candidate.update!(category_id: category.id)
          else
            Whatsapp::ReplySender.send_to(clarification.phone_number,
                                          "Ok, escríbelo con texto por favor. #{Questions.build_text(pending)}")
            return :ask_free_text
          end

          candidate.recalculate_missing_fields!
          candidate.recalculate_status!

          if clarification.all_candidates_resolved?
            complete_session!(clarification)
            :completed
          else
            follow_up(clarification)
          end
        end
      rescue StandardError => e
        Rails.logger.error("[Clarification::Resolver] tap failed: #{e.message}")
        Whatsapp::ReplySender.send_to(clarification.phone_number,
                                      "Tuve un problema procesando tu respuesta, inténtalo de nuevo 🙏")
        :error
      end

      def candidates_context(clarification)
        clarification.pending_candidates.each_with_index.map do |candidate, index|
          {
            index: index + 1,
            description: candidate.description,
            amount: candidate.amount,
            date: candidate.date,
            category: candidate.category&.name || candidate.category_suggestion,
            money_source: candidate.money_source&.name,
            missing_fields: candidate.missing_fields
          }
        end
      end

      def money_source_identifiers(user)
        user.money_sources.active.includes(recognition: :recognition_identifiers)
            .flat_map { |source| [ source.name, source.recognition_identifiers.select(&:confirmed?).map(&:value) ] }
      end

      # Applies each resolution entry to its candidate by question index.
      # ONLY missing fields are written — resolved data is never overwritten.
      # Unresolved / unknown-index / unresolvable values leave the candidate
      # untouched. Returns the number of candidates modified.
      def apply_resolutions!(clarification, resolutions)
        pending = clarification.pending_candidates.to_a
        modified = 0

        resolutions.each do |entry|
          index = (entry[:index] || entry["index"]).to_i
          resolved = entry[:resolved] || entry["resolved"] || {}
          unresolved = entry[:unresolved] || entry["unresolved"] || resolved.blank?

          candidate = pending[index - 1]
          next if candidate.nil? || unresolved

          if apply_updates!(candidate, resolved)
            candidate.recalculate_missing_fields!
            candidate.recalculate_status!
            modified += 1
          end
        end
        modified
      end

      def apply_updates!(candidate, updates)
        missing = candidate.missing_fields
        changed = false

        if missing.include?("amount")
          amount = parse_amount(updates["amount"])
          if amount.present? && amount.positive?
            candidate.amount = amount
            changed = true
          end
        end

        if missing.include?("date")
          date = ExpenseCandidate.parse_date(updates["date"])
          if date.present?
            candidate.date = date
            changed = true
          end
        end

        if missing.include?("description") && updates["description"].present?
          candidate.description = updates["description"].to_s.strip.presence
          changed = true
        end

        if missing.include?("category_id") && updates["category"].present?
          resolved = Categories::ClosestResolver.call(user: candidate.user, name: updates["category"])
          category = resolved.category ||
                     Category.create!(name: updates["category"].split.map(&:capitalize).join(" "),
                                      user: candidate.user, is_default: false, category_type: "expense")
          candidate.category_id = category.id
          changed = true
        end

        if missing.include?("money_source_id") && updates["money_source_hint"].present?
          source = MoneySources::Detector.call(user: candidate.user, text: updates["money_source_hint"])
          if source
            candidate.money_source_id = source.id
            changed = true
          end
        end

        candidate.save! if changed
        changed
      end

      def parse_amount(value)
        return nil if value.blank?

        BigDecimal(value.to_s.gsub(/[^\d.\-]/, ""))
      rescue ArgumentError, TypeError
        nil
      end

      # Converts every now-complete candidate immediately (idempotent via
      # confirm!) and closes the session when nothing is left pending.
      def complete_session!(clarification)
        clarification.candidates.where(status: "ready", expense_id: nil).find_each do |candidate|
          candidate.confirm!
          Whatsapp::ReplySender.send_to(
            clarification.phone_number,
            "✅ Gasto registrado: $#{format_amount(candidate.amount)} – #{candidate.description.presence || 'sin descripción'}"
          )
        end
        clarification.close!(:resolved) if clarification.all_candidates_resolved?
      end

      # Sends the next grouped question and either keeps the session pending
      # or abandons it once the follow-up limit is reached (remaining
      # candidates stay needs_review — no infinite loops).
      def follow_up(clarification, custom_question = nil)
        if clarification.follow_ups_exhausted?
          abandon(clarification)
          return :abandoned
        end

        question = custom_question || Questions.build_text(clarification.pending_candidates)
        Whatsapp::ReplySender.send_to(clarification.phone_number, question)
        clarification.update!(question: question, questions_count: clarification.questions_count + 1)
        :follow_up
      end

      def abandon(clarification)
        clarification.close!(:abandoned)
        Whatsapp::ReplySender.send_to(
          clarification.phone_number,
          "Dejé la aclaración pendiente; los gastos quedaron guardados para revisión manual en el Expense Tracker."
        )
      end

      def format_amount(amount)
        ActionController::Base.helpers.number_to_currency(amount, unit: "", delimiter: ".", separator: ",",
                                                          precision: 0)
      end
    end
  end
end
