# frozen_string_literal: true

module SourceRecognition
  # SuggestionEngine
  # Computes deterministic, non-persisted suggestions for a Money Source so the
  # recognition page can pre-fill configuration without requiring manual typing.
  #
  # Rules:
  #   1. Values DISCOVERED during Gmail syncs are persisted as suggestions
  #      (status "suggested", origin "gmail") and surface here with
  #      provenance :gmail, ordered by observations.
  #   2. From the source's own name/bank (first-time configuration).
  #   3. From sibling sources of the SAME institution: reuse their senders,
  #      domains and subject/header patterns (with provenance). Product-specific
  #      keywords on a sibling are never copied — only the shared institution
  #      token is suggested as a keyword.
  #   4. Values already CONFIRMED on the current source are excluded.
  #
  # Output shape:
  #   {
  #     keywords: [ { value:, source:, count: }, ... ],  # source ∈ :gmail | :name | :institution | :last_four | sibling name
  #     senders:  [ { value:, source: }, ... ],
  #     subjects: [ { value:, source: }, ... ]
  #   }
  #
  # The computed suggestions persist via #persist!: own-computed values are
  # stored as suggested rows (origin = the provenance token) so the group
  # cards count every pending value until it is applied or dismissed.
  class SuggestionEngine    Suggestion = Struct.new(:value, :source, :product_specific, keyword_init: true)

    # Words that read as generic (money / bank / card) are not useful distinct
    # keywords and are skipped as name-derived suggestions.
    STOP_KEYWORDS = %w[
      cuenta cuentaahorro tarjeta tarjetas credito debitodavivienda ahorro
      banco financing cuotas lineadcredito sorgo savings bank money card account
    ].freeze

    # Cash wallets live off any "cash" wording (an ATM note, a transfer note
    # or a plain text like "pagué la plata"): every cash source gets these
    # kind-level keyword suggestions, whatever its actual name is.
    CASH_KIND_KEYWORDS = %w[efectivo plata dinero cash billete].freeze

    INSTITUTION_TOKENS = %w[banco bancolombia davibank davienda bancopopular
                            bancocaja bbva santander avvillas pibranchcolpatria
                            bancolombia].freeze

    # `group_members` feeds the BANK drawer: its persisted suggestions for
    # the bank-level kinds (senders/domains/subjects) are aggregated from
    # every member the Gmail discovery touched, so the user reviews them in
    # ONE place instead of per card. Product keywords stay per source.
    def initialize(source:, group_members: [])
      @source = source
      @group_members = group_members
    end

    def call
      @call ||= {
        keywords: merge_persisted(%w[keyword], keyword_suggestions),
        senders: merge_persisted(%w[sender domain], sender_suggestions),
        subjects: merge_persisted(%w[subject header], subject_suggestions)
      }
    end

    # Persists the computed suggestions (status "suggested", origin = the
    # provenance token) so the group cards count them — gmail-discovered AND
    # own-computed alike — until each value is applied (promoted) or
    # dismissed (tombstoned). Existing CONFIRMED values block; SUGGESTED rows
    # are already persisted; DISMISSED tombstones block forever. The
    # discovery cap bounds the noise from messy names.
    def persist!
      created = 0
      recognition = source.ensure_recognition
      recognition.save! if recognition.new_record?

      call.each do |section, suggestions|
        suggestions.each do |suggestion|
          kind = SourceRecognition::ValueClassifier.kind_of(section.to_s, suggestion[:value])
          origin = suggested_origin(suggestion[:source])
          value = MoneySourceRecognitionIdentifier.normalize(suggestion[:value])
          next if value.blank? || origin.blank?
          next if recognition.recognition_identifiers.exists?(kind: kind, value: value)
          next if recognition.recognition_identifiers.where(kind: kind).count >= SourceRecognition::DiscoveryService::MAX_PER_KIND

          recognition.recognition_identifiers.create!(
            kind: kind, value: value, status: "suggested", origin: origin,
            position: next_position(recognition, kind)
          )
          created += 1
        rescue ActiveRecord::RecordNotUnique
          0
        end
      end
      recognition.recognition_identifiers.reload
      created
    end

    private

    attr_reader :source

    # Maps the suggestion provenance to the persisted origin token. Sibling
    # reuse collapses to "sibling" (the specific name is dynamic).
    def suggested_origin(source_label)
      # Only token provenances persist (own guesses); :gmail rows are already
      # persisted and sibling-reuse values (String provenance) are already
      # persisted on the sibling — copying them would double-count.
      return nil unless source_label.is_a?(Symbol) && source_label != :gmail

      MoneySourceRecognitionIdentifier::ORIGINS.include?(source_label.to_s) ? source_label.to_s : nil
    end

    def next_position(recognition, kind)
      recognition.recognition_identifiers.where(kind: kind).maximum(:position).to_i.succ
    end

    # Values discovered during Gmail syncs (persisted, status "suggested")
    # surface as suggestions with :gmail provenance, most-observed first.
    # When banking-level kinds are rendered for a group (bank drawer), the
    # members' suggestions join the pool — provenance shows the member name.
    def persisted_suggestions(kinds)
      bank_level_section = kinds.exclude?("keyword")
      unless bank_level_section
        return source.recognition_identifiers
                     .select { |id| id.suggested? && id.kind.in?(kinds) }
                     .sort_by { |id| -id.observation_count }
                     .map { |id| { value: id.value, source: persisted_source(id), count: id.observation_count } }
      end

      ([ source ] + Array(@group_members))
        .flat_map do |origin|
          rows = if origin == source
                   origin.recognition_identifiers
                 else
                   origin.recognition_identifiers.select { |id| !id.keyword? }
                 end
          rows.select { |id| id.suggested? && id.kind.in?(kinds) }
              .sort_by { |id| -id.observation_count }
              .map do |id|
                { value: id.value,
                  source: persisted_source(id, origin: origin),
                  count: id.observation_count }
              end
        end
        .sort_by { |suggestion| -suggestion[:count] }
    end

    # Provenance of a persisted row: gmail rows keep :gmail (or the owning
    # member's name in the bank drawer); own-computed rows map their stored
    # origin token back to the engine provenance symbol.
    def persisted_source(id, origin: nil)
      return origin.name if origin && origin != source && id.origin == "gmail"

      case id.origin
      when "gmail" then :gmail
      when "name" then :name
      when "institution" then :institution
      when "kind" then :kind
      when "last_four" then :last_four
      else :sibling
      end
    end

    # Merge order: gmail-discovered rows first (strongest provenance), then
    # the computed suggestions (own-computed provenance), then any own-computed
    # persisted rows not recomputed this time. Deduped case-insensitively.
    def merge_persisted(kinds, computed)
      persisted = persisted_suggestions(kinds)
      gmail_rows = persisted.select { |s| s[:source] == :gmail }
      persisted = persisted - gmail_rows
      (gmail_rows + computed + persisted).uniq { |s| s[:value].to_s.downcase }
    end

    # Only CONFIRMED values block suggestions: persisted suggestions must
    # keep surfacing until the user accepts or dismisses them.
    def existing_values
      @existing_values ||= source.recognition_identifiers
                                 .reject(&:suggested?)
                                 .group_by(&:kind)
                                 .transform_values { |ids| ids.map(&:value).to_set }
    end

    def new_value?(kind, value)
      normalized = MoneySourceRecognitionIdentifier.normalize(value)
      !existing_values.fetch(kind, []).include?(normalized)
    end

    def siblings
      # "Same institution" primarily compares the polymorphic institution
      # association; legacy free-text banks fall back to normalized string
      # equality of the bank token. Only payment sources may hold
      # recognition, so loans/pockets never contribute or receive suggestions.
      payment_sources = MoneySource
                        .where(user_id: source.user_id)
                        .payment_sources
                        .where.not(id: source.id)
                        .includes(:recognition_identifiers)
                        .select { |s| s.recognition_identifiers.any? }

      @siblings ||= payment_sources.select { |s| same_institution?(s) }
    end

    def same_institution?(other)
      if source.institution?
        return false unless other.institution?

        other.institution_type == source.institution_type &&
          other.institution_id == source.institution_id
      else
        other.institution? ? false : other.institution_token == source.institution_token
      end
    end

    # --- keywords ------------------------------------------------------------

    def keyword_suggestions
      result = []
      result << { value: source.last_four, source: :last_four } if last_four_suggested?
      result.concat kind_keywords
      result.concat name_keywords
      result << { value: institution_keyword_token, source: :institution } if institution_token_eligible?
      result.uniq { |s| s[:value] }
    end

    # The shared institution keyword: the folded name of the ATTACHED entity,
    # or the legacy downcased bank token for unattached rows.
    def institution_keyword_token
      if source.institution?
        TextNormalizer.fold(source.institution_name).presence
      else
        source.institution_token
      end
    end

    # Kind-level keywords (cash wallets → efectivo/plata/dinero/cash/billete):
    # generic money words every source of that kind can be recognized by.
    # The shared-brand ambiguity guard does NOT apply — several cash wallets
    # is the normal case, and cash words are never product discriminators.
    # Still respect what the user already confirmed on the source.
    def kind_keywords
      return [] unless source.kind == "cash"

      CASH_KIND_KEYWORDS
        .reject { |word| STOP_KEYWORDS.include?(word) }
        .filter_map do |word|
          { value: word, source: :kind } if new_value?("keyword", word)
        end
    end

    # The account/card's last four digits are the strongest discriminator
    # between two sources of the same bank: suggested first, never copied to
    # siblings (it is product-specific by definition).
    def last_four_suggested?
      source.last_four.present? && new_value?("keyword", source.last_four)
    end

    # Tokens from the source's own name/bank, lowercased, accent-stripped.
    # Tokens shared by several of the user's sources (the classic shared
    # card-brand token) never discriminate and are skipped.
    def name_keywords
      tokens = TextNormalizer.name_tokens(source.name.to_s + " " + source.bank.to_s,
                                          stop_words: STOP_KEYWORDS)

      tokens.select { |t| new_value?("keyword", t) }
            .reject { |t| ambiguous_tokens.include?(t) }
            .uniq
            .map { |t| { value: t, source: :name } }
    end

    def ambiguous_tokens
      @ambiguous_tokens ||= AmbiguousTokens.for_user(source.user)
    end

    # Only the shared institution token qualifies as a keyword suggested from
    # a sibling — never a sibling's product tokens.
    def institution_token_eligible?
      institution_keyword_token.present? &&
        !existing_values.fetch("keyword", []).include?(institution_keyword_token) &&
        siblings.any?
    end

    # --- senders / domains ---------------------------------------------------

    def sender_suggestions
      result = siblings.flat_map do |sibling|
        values = sibling.recognition_identifiers
                        .select { |id| id.kind == "sender" || id.kind == "domain" }
                        .map(&:value)
        values.map { |v| { value: v, source: sibling.name } }
      end.filter { |s| new_value?("sender", s[:value]) && new_value?("domain", s[:value]) }
         .uniq { |s| s[:value].downcase }

      # No configured sibling yet: bank notification emails usually come from
      # the bank's own domain, so propose "<institution>.com" as a close guess
      # (only for single-token institutions; the user can always reject it).
      if result.empty? && bank_domain_suggestion
        result << bank_domain_suggestion
      end
      result
    end

    def bank_domain_suggestion
      # Attached to a catalog entity: suggest one of its verified domains
      # (candidate signal the user still must accept). Keyed by type/id
      # columns + a point lookup so hot paths stay association-free (the
      # display label lives in institution_cached_name).
      if source.institution_type == "FinancialInstitution"
        catalog_entity = FinancialInstitution.find_by(id: source.institution_id)
        domain = catalog_entity&.domains&.first
      end

      # Legacy fallback: "<bank-token>.com" for unattached single-token bank.
      unless domain
        inst = source.institution_token
        return nil if inst.blank? || inst.include?(" ")

        domain = "#{inst}.com"
      end

      return nil unless new_value?("sender", domain) && new_value?("domain", domain)

      { value: domain, source: :institution }
    end

    # --- subjects / headers --------------------------------------------------

    def subject_suggestions
      siblings.flat_map do |sibling|
        sibling.recognition_identifiers
               .select { |id| id.kind == "subject" || id.kind == "header" }
               .map { |id| { value: id.value, source: sibling.name } }
      end.filter { |s| new_value?("subject", s[:value]) && new_value?("header", s[:value]) }
         .uniq { |s| s[:value] }
    end
  end
end
