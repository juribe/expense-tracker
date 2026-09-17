# frozen_string_literal: true

module Expenses
  module Processors
    # THE core of the expense processor: converts TEXT into an
    # ExpenseCandidate. Every other channel ends up here - Audio transcribes
    # to text, Image OCRs to text (or normalizes its vision entry directly) -
    # because the normalization, category resolution, validation and the
    # expense-candidate mapping are shared by all of them.
    #
    #   candidate, engine = Processors::Text.new(user:, input:, ...).call("Me gasté 50mil", context:)
    #
    # It NEVER persists anything.
    class Text < Base
      # Digital subscriptions/services (any case/format) that must never resolve
      # to "Servicios públicos": those are actual utilities (water, electricity,
      # gas, internet, phone). Kept as a deterministic guard so a small model
      # cannot hard-push a wrong utilities label that would survive reconfirm.
      NON_UTILITY_DIGITAL_TERMS = %w[
        netflix spotify disney canva chatgpt openai microsoft adobe icloud
        dropbox google-one prime hbo max paramount crunchyroll youtube
      ].freeze

      # Streaming services classify as "Entretenimiento" (they are not utilities).
      STREAMING_TERMS = %w[netflix spotify disney hbo max paramount crunchyroll youtube].freeze

      # Parking-fee keywords that deterministically classify as "Transporte" when
      # the user has that category (mirrors ClosestResolver::PARKING_TERMS).
      PARKING_TERMS = %w[parking parqueadero parqueo estacionamiento].freeze

      # Words stripped when building a suggested NEW category name from an
      # unmatched activity, so the suggestion reads like a name, not a sentence.
      SUGGESTION_STOP_WORDS = %w[
        pague pago gasto gaste pagar compre compro gastamos solo en de del al la
        las los un una unos unas que con para por y o a tambien fueron me mi era
        son es mil lucas pesos
      ].freeze

      # The full text -> candidate pipeline. Returns [candidate, engine]; the
      # candidate is nil only when extraction found nothing to parse. When
      # called as the text-channel processor (no text given) the text comes
      # from the input itself; audio and image processors pass their derived
      # text explicitly.
      def call(text = nil, context: nil)
        entry, engine = parse_into_entry(text || note, context: context)
        return [ nil, engine ] if entry.nil?

        candidate = normalize(entry)
        validate(candidate)
        [ candidate, engine ]
      end

      # Maps an already-extracted raw entry (e.g. from the image vision path)
      # into a normalized ExpenseCandidate, resolving categories and running
      # the deterministic business guards.
      def normalize(entry)
        category = resolve_category(entry[:category_name], entry[:category_id], activity: entry[:description].presence || entry[:merchant])
        extracted_name = @rejected_category_name ? nil : entry[:category_name].presence
        candidate = ExpenseCandidate.new(
          amount: entry[:amount],
          currency: entry[:currency].presence || ExpenseCandidate::DEFAULT_CURRENCY,
          category_id: category&.id,
          category_name: category&.name || extracted_name,
          description: entry[:description].presence || entry[:merchant].presence,
          merchant: entry[:merchant],
          date: parse_date(entry[:transaction_date]),
          source: "playground",
          confidence: entry[:confidence],
          money_source_id: entry[:money_source_id].presence&.to_i,
          money_source_name: entry[:money_source_name].presence
        )
        if category.nil?
          if candidate.category_name.present?
            @warnings << "We could not match the category \"#{candidate.category_name}\". You can create it or pick an existing one when you confirm."
          elsif (suggested = suggest_category_name(entry[:description].presence || entry[:merchant].presence))
            candidate.category_name = suggested
            candidate.suggested_category_name = suggested
            @warnings << "No matching category found. Suggesting the new category \"#{suggested}\"; confirm to create it or pick an existing one."
          elsif @warnings.grep(/category for this expense/i).empty?
            @warnings << "We could not determine a category for this expense. You can assign it when you confirm."
          end
        end

        @steps[:normalization] = {
          amount: candidate.amount,
          currency: candidate.currency,
          category_id: candidate.category_id,
          category_name: candidate.category_name,
          date: candidate.date&.iso8601,
          money_source_id: candidate.money_source_id,
          money_source_name: entry[:money_source_name],
          matching: if @category_resolution&.matched?
                      {
                        input: entry[:category_name],
                        matched_by: @category_resolution.matched_by,
                        mapped_to: candidate.category_name,
                        similarity: @category_resolution.similarity
                      }
                    end,
          warnings: @warnings
        }
        candidate
      end

      def validate(candidate)
        @steps[:validation] = {
          valid: candidate.valid?,
          checks: candidate.checks,
          errors: candidate.errors
        }
      end

      private

      def parse_into_entry(text, context: nil)
        result = ExpenseParser.call(text: text, user: @user, context: context, execution: @execution)
        entry = result[:expenses].first
        @warnings.concat(Array(result[:errors]))
        if entry.nil?
          reason = @warnings.grep(/amount/i).first.presence || "no expense could be detected in the text."
          @errors << "Could not extract an expense from this input. Reason: #{reason}"
          return [ nil, result[:engine] ]
        end

        entry = entry.merge!(merchant: nil, currency: ExpenseCandidate::DEFAULT_CURRENCY)
        @warnings.concat(Array(entry[:warnings]))

        @steps[:extraction] = {
          engine: result[:engine],
          ai_strategy: result[:ai_strategy],
          raw: result[:expenses],
          detected_count: result[:expenses].length
        }
        [ entry, result[:engine] ]
      end

      # Category resolution is centralized in Categories::ClosestResolver:
      # exact normalized name, learned activity mappings (ActivityClassification),
      # English -> Spanish aliases and a similarity fold, so a category name that
      # is "very close" to an existing one never creates a near-duplicate. There
      # are no unconditional rules and an absent category stays unassigned.
      # Processors NEVER persist, so similarity folds are resolved but not
      # recorded as knowledge here.
      #
      # Two deterministic business guards run AFTER resolution: parking text
      # always classifies as "Transporte" when the user has it, and a digital
      # subscription (Netflix, Canva, Microsoft 365, ...) is never "Servicios
      # públicos" — it stays unassigned so a suggestion is built instead. These
      # exist so small models cannot hard-push a wrong label that would persist.
      def resolve_category(category_name, category_id, activity: nil)
        categories = Category.for_user(@user)
        @category_resolution = nil
        @rejected_category_name = false
        resolved =
          if category_id.present?
            categories.find_by(id: category_id)
          elsif category_name.present? || activity.present?
            # An absent extracted name stays unassigned unless a deterministic rule
            # or the user's stored knowledge classifies the activity. ClosestResolver
            # applies NO unconditional rules; user knowledge wins when present.
            @category_resolution = Categories::ClosestResolver.call(
              user: @user,
              name: category_name.to_s,
              activity: activity,
              record: false
            )
            @category_resolution.category
          end

        apply_business_guards(resolved, category_name, activity, categories)
      end

      # Enforces the deterministic business rules after any resolution (AI id,
      # ClosestResolver, or none) so a wrong label can never slip through. The
      # raw user note is included so the guards see "Microsoft 365"/"parqueadero"
      # even when the model slimmed the description down.
      def apply_business_guards(resolved, category_name, activity, categories)
        text = [ category_name, activity, note ].compact.join(" ").to_s.downcase
        return resolved if text.blank?

        transporte = categories.find { |category| ActivityClassification.normalize_name(category.name) == "transporte" }
        if transporte && PARKING_TERMS.any? { |term| text.include?(term) }
          @category_resolution = Categories::ClosestResolver::Result.new(category: transporte, matched_by: :parking, similarity: 1.0)
          return transporte
        end

        utilities = categories.find { |category| ActivityClassification.normalize_name(category.name) == "servicios publicos" }
        if utilities && resolved&.id == utilities.id &&
           NON_UTILITY_DIGITAL_TERMS.any? { |term| text.include?(term) }
          @rejected_category_name = true
          @category_resolution = nil
          return nil
        end

        resolved
      end

      def parse_date(value)
        return Date.current if value.blank?

        begin
          Date.iso8601(value.to_s)
        rescue ArgumentError, Date::Error, TypeError
          Date.parse(value.to_s)
        end
      rescue ArgumentError, Date::Error, TypeError
        nil
      end

      # Builds a short, name-like NEW category from an unmatched activity so a
      # blank category never stays empty:
      #   - streaming services (Netflix, Spotify, ...) suggest "Entretenimiento"
      #   - other digital SaaS (Canva, Microsoft 365, ChatGPT, ...) suggest a new
      #     "Suscripciones" category
      #   - anything else falls back to the cleaned, title-cased activity
      # Returns nil only when nothing scannable remains.
      def suggest_category_name(text)
        return nil if text.blank?

        normalized = ActivityClassification.normalize_name(text).to_s
        return "Entretenimiento" if STREAMING_TERMS.any? { |term| normalized.include?(term) }
        if (NON_UTILITY_DIGITAL_TERMS - STREAMING_TERMS).any? { |term| normalized.include?(term) }
          return "Suscripciones"
        end

        tokens = normalized.split.reject do |token|
          SUGGESTION_STOP_WORDS.include?(token) || token.match?(/\A\d+\z/)
        end
        title = tokens.join(" ")
        return nil if title.blank?

        title.split.map(&:capitalize).join(" ").truncate(40)
      end
    end
  end
end
