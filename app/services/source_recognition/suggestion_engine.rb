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
  # The engine never writes to the database.
  class SuggestionEngine
    Suggestion = Struct.new(:value, :source, :product_specific, keyword_init: true)

    # Words that read as generic (money / bank / card) are not useful distinct
    # keywords and are skipped as name-derived suggestions.
    STOP_KEYWORDS = %w[
      cuenta cuentaahorro tarjeta tarjetas credito debitodavivienda ahorro
      banco financing cuotas lineadcredito sorgo savings bank money card account
    ].freeze

    INSTITUTION_TOKENS = %w[banco bancolombia davibank davienda bancopopular
                            bancocaja bbva santander avvillas pibranchcolpatria
                            bancolombia].freeze

    def initialize(source:)
      @source = source
    end

    def call
      {
        keywords: merge_persisted(%w[keyword], keyword_suggestions),
        senders: merge_persisted(%w[sender domain], sender_suggestions),
        subjects: merge_persisted(%w[subject header], subject_suggestions)
      }
    end

    private

    attr_reader :source

    # Values discovered during Gmail syncs (persisted, status "suggested")
    # surface as suggestions with :gmail provenance, most-observed first.
    def persisted_suggestions(kinds)
      source.recognition_identifiers
            .select { |id| id.suggested? && id.kind.in?(kinds) }
            .sort_by { |id| -id.observation_count }
            .map { |id| { value: id.value, source: :gmail, count: id.observation_count } }
    end

    # Persisted Gmail suggestions take precedence over computed ones; the
    # combined list is deduped case-insensitively.
    def merge_persisted(kinds, computed)
      (persisted_suggestions(kinds) + computed)
        .uniq { |s| s[:value].to_s.downcase }
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
      @siblings ||= begin
        inst = source.institution
        return [] if inst.blank?

        # "Same institution" compares normalized bank strings: users type
        # "Davibank" / "davibank" freely, so match case-insensitively.
        MoneySource
          .where(user_id: source.user_id)
          .where.not(id: source.id)
          .where("LOWER(TRIM(COALESCE(bank, ''))) = :inst", inst: inst)
          .includes(:recognition_identifiers)
          .reject { |s| s.recognition_identifiers.empty? }
      end
    end

    # --- keywords ------------------------------------------------------------

    def keyword_suggestions
      result = []
      result << { value: source.last_four, source: :last_four } if last_four_suggested?
      result.concat name_keywords
      result << { value: source.institution, source: :institution } if institution_token_eligible?
      result.uniq { |s| s[:value] }
    end

    # The account/card's last four digits are the strongest discriminator
    # between two sources of the same bank: suggested first, never copied to
    # siblings (it is product-specific by definition).
    def last_four_suggested?
      source.last_four.present? && new_value?("keyword", source.last_four)
    end

    # Tokens from the source's own name/bank, lowercased, accent-stripped.
    def name_keywords
      tokens = (source.name.to_s + " " + source.bank.to_s).unicode_normalize(:nfkd)
               .gsub(/[^\p{Alnum}\s]/i, " ")
               .downcase
               .split(/\s+/)
               .reject { |t| t.length < 3 }
               .reject { |t| STOP_KEYWORDS.include?(t) }

      tokens.select { |t| new_value?("keyword", t) }
            .uniq
            .map { |t| { value: t, source: :name } }
    end

    # Only the shared institution token qualifies as a keyword suggested from
    # a sibling — never a sibling's product tokens.
    def institution_token_eligible?
      source.institution.present? &&
        !existing_values.fetch("keyword", []).include?(source.institution) &&
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
      inst = source.institution
      return nil if inst.blank? || inst.include?(" ")

      value = "#{inst}.com"
      return nil unless new_value?("sender", value) && new_value?("domain", value)

      { value: value, source: :institution }
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
