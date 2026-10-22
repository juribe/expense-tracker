# frozen_string_literal: true

module SourceRecognition
  # Matches a fetched email against the recognition configuration of the
  # user's Money Sources. This is the consumption side of the identifiers the
  # user configures on the recognition page.
  #
  # Matching rules (all comparisons case-insensitive, accent-folded):
  #   sender  — From address equals the value (or display name contains it)
  #   domain  — From address's domain equals the value (subdomains allowed)
  #   subject — subject contains the value
  #   header  — "Name: value" pattern checked against the message headers
  #   keyword — body contains the value respecting word boundaries
  #
  # Special rule for the source's last-four digits: a 4-digit keyword that
  # equals source.last_four is ONLY matched when anchored, i.e. it is the
  # tail of a longer digit run ("47512300005678"), preceded by masking
  # characters ("•••• 5678" / "****5678") or a "terminada en 5678" phrase.
  # A bare 4-digit token in the body (an amount, a date) never matches.
  #
  # Institution signals (sender/domain/subject/header) identify the BANK, not
  # the product: every card of the same bank shares them. They are zeroed out
  # for everyone when two different bank groups match at institution level, or
  # when the matched group has several configured members and one of them
  # matched product evidence. Only product evidence (keywords, anchored
  # last-four) may then pick a winner; without it the result stays ambiguous
  # instead of rewarding whoever confirmed more bank boilerplate, and the
  # seed's sender/domain cannot keep the email away from the card that
  # provably paid.
  #
  #   Matcher.call(user: user, message: gmail_message_hash)
  #     => MoneySource            when exactly one source wins
  #     => [MoneySource, ...]     when the top score is tied (ambiguous)
  #     => nil                    when nothing matches
  #
  # Only CONFIRMED identifiers participate: persisted suggestions
  # (status "suggested") are awaiting user review and dismissed identifiers
  # (status "dismissed") were rejected by the user; neither must drive
  # automatic matching.
  class Matcher
    WEIGHTS = { "sender" => 3, "domain" => 3, "subject" => 2, "header" => 2, "keyword" => 1 }.freeze
    LAST_FOUR_WEIGHT = 4
    INSTITUTION_KINDS = %w[sender domain subject header].freeze
    MASK_PREFIX = /[*•#]+\s*/.freeze
    TERMINATION_PHRASE = /terminad[ao]s?\s+en|termina(?:n|do)?\s+en\s+los?\s+d[ií]gitos|termina\s+en|ending\s+in/.freeze

    class << self
      def call(user:, message:)
        new(user: user, message: message).call
      end

      # True when the body shows the value as an ANCHORED last-four reference
      # (masked prefix, tail of a long digit run, or "terminada en" phrase).
      # Used by the discovery service to propose source last-four keywords.
      def last_four_in_body?(body, value)
        new(user: nil, message: { body_text: body }).send(:anchored_last_four?, value)
      end
    end

    def initialize(user:, message:)
      @user = user
      @message = message || {}
      @from = @message[:from].to_s
      @subject = fold(@message[:subject])
      @body = fold(@message[:body_text])
      @headers = Array(@message[:headers])
    end

    def call
      scored = sources.filter_map do |source|
        score = score_for(source)
        [ source, score ] if score.positive?
      end
      Rails.logger.debug do
        "[SourceRecognition::Matcher] user=#{@user&.id} institution_ambiguous=#{institution_ambiguous?} " \
          "scores=#{scored.map { |source, score| "#{source.name}=#{score}" }.join(', ')}"
      end
      return nil if scored.empty?
      return scored.first.first if scored.one?

      ranked = scored.sort_by { |_, score| -score }
      return ranked.first.first if ranked.first.last > ranked.second.last

      ranked.map(&:first)
    end

    private

    def sources
      @sources ||= begin
        groups = bank_groups
        @user.money_sources
             .payment_sources
             .includes({ recognition: :recognition_identifiers })
             .select do |source|
               source.recognition_configured? || group_configured?(source)
             end
      end
    end

    def score_for(source)
      # Legacy multi-configured banks keep the original semantics unchanged:
      # every source scores its OWN confirmed identifiers (with the ambiguity
      # zeroing of bank boilerplate when several sources match).
      #
      # When a bank group has exactly ONE configured source (the SEED — the
      # redesigned per-bank config), siblings ride the seed's confirmed
      # sender/domain/subject/header evidence through the group: product
      # evidence (keywords, anchored last-four) always lives on the individual
      # source, and bank signals can never rank siblings.
      self_score = per_source_score(source)

      if shared_bank_evidence_applicable?(source)
        self_score + shared_bank_evidence(source)
      else
        self_score
      end
    end

    # --- bank groups ------------------------------------------------------------

    # Member pools keyed by institution: the attached polymorphic entity, or
    # — legacy unattached rows — the folded bank token. A group carries
    # exactly one SEED (its earliest member): the source whose recognition
    # record holds the bank-level configuration the whole group shares.
    def bank_groups
      key_by_id = {}
      buckets = Hash.new { |hash, key| hash[key] = { key: key, members: [] } }
      @user.money_sources.payment_sources
          .includes({ recognition: :recognition_identifiers })
          .each do |source|
            key = bank_group_key(source)
            key_by_id[source.id] = key
            buckets[key][:members] << source
          end

      buckets.values.each do |group|
        group[:seed] = group[:members].min_by { |member| [ member.created_at, member.id ] }
        group[:configured] = group[:members].any?(&:recognition_configured?)
      end

      buckets
    end

    def bank_group_key(source)
      BankGrouping.key(source)
    end

    def bank_group_for(source)
      bank_groups[bank_group_key(source)]
    end

    def group_configured?(source)
      group = bank_group_for(source)
      group ? group[:configured] : false
    end

    # --- scoring ----------------------------------------------------------------

    def per_source_score(source)
      source.recognition_identifiers
            .select { |id| active_identifier?(id) }
            .sum { |id| identifier_score(id, source) }
    end

    def identifier_score(id, source)
      # Between configured siblings of the same bank the boilerplate matches
      # for everyone, so it carries no information about which card was used.
      return 0 if institution_ambiguous? && INSTITUTION_KINDS.include?(id.kind)

      case id.kind
      when "sender"  then sender_matches?(id.value) ? WEIGHTS["sender"] : 0
      when "domain"  then domain_matches?(id.value) ? WEIGHTS["domain"] : 0
      when "subject" then @subject.include?(fold(id.value)) ? WEIGHTS["subject"] : 0
      when "header"  then header_matches?(id.value) ? WEIGHTS["header"] : 0
      when "keyword" then keyword_score(id, source)
      else 0
      end
    end

    # Shared bank evidence applies only when the group has EXACTLY ONE
    # configured source (the seed) and the source addressed here is NOT it:
    # the seed owns the bank-level configuration, the sibling rides it.
    def shared_bank_evidence_applicable?(source)
      group = bank_group_for(source)
      return false unless group

      configured = group[:members].select(&:recognition_configured?)
      configured.size == 1 && configured.first.id != source.id
    end

    # Non-configured siblings score the seed's CONFIRMED bank-level
    # identifiers (sender/domain/subject/header) at a LOWER weight: the bank
    # alone must never outrank the seed's own evidence nor decide a product;
    # product evidence (own keywords/last-four) always breaks such ties.
    # Shared evidence is zeroed by the same ambiguity rule as every other
    # bank signal.
    SHARED_WEIGHTS = { "sender" => 2, "domain" => 2, "subject" => 1, "header" => 1 }.freeze

    def shared_bank_evidence(source)
      seed = bank_group_for(source)[:seed]
      seed.recognition_identifiers
          .select { |id| active_identifier?(id) }
          .select { |id| INSTITUTION_KINDS.include?(id.kind) && shared_bank_match?(id) }
          .sum { |id| SHARED_WEIGHTS[id.kind] }
    end

    def shared_bank_match?(id)
      return false if institution_ambiguous?

      case id.kind
      when "sender"  then sender_matches?(id.value)
      when "domain"  then domain_matches?(id.value)
      when "subject" then @subject.include?(fold(id.value))
      when "header"  then header_matches?(id.value)
      else false
      end
    end

    def institution_ambiguous?
      return @institution_ambiguous if defined?(@institution_ambiguous)

      # Bank-level evidence identifies a BANK GROUP, not a product. It is
      # ambiguous when:
      #   - TWO DIFFERENT groups matched at bank level (one relay email may
      #     name several banks), or
      #   - the matched group has SEVERAL configured members (account plus
      #     cards of the same bank) AND at least one of them matched product
      #     evidence in the message. The seed holds the shared sender/domain/
      #     subject boilerplate, so it must not single out a product when a
      #     sibling can prove it was the one used.
      matched_groups = bank_groups.values.select do |group|
        group[:members]
             .select(&:recognition_configured?)
             .any? { |source| institution_match?(source) }
      end
      @institution_ambiguous = matched_groups.size >= 2 ||
                               matched_groups.any? do |group|
                                 group[:members].count(&:recognition_configured?) >= 2 &&
                                   group[:members].any? { |source| product_match?(source) }
                               end
    end

    # Product evidence (a matching keyword, including anchored last-four)
    # proves WHICH member of a bank group was used. It does not depend on
    # institution_ambiguous?, so it is safe to evaluate while deciding it.
    def product_match?(source)
      source.recognition_identifiers.any? do |id|
        next false unless active_identifier?(id) && id.kind == "keyword"

        keyword_score(id, source).positive?
      end
    end

    def institution_match?(source)
      source.recognition_identifiers
            .select { |id| active_identifier?(id) }
            .any? { |id| INSTITUTION_KINDS.include?(id.kind) && institution_kind_match?(id) }
    end

    # Suggestions await user review; dismissed identifiers were rejected by
    # the user. Neither may drive automatic matching.
    def active_identifier?(id)
      !id.suggested? && !id.dismissed?
    end

    def institution_kind_match?(id)
      case id.kind
      when "sender"  then sender_matches?(id.value)
      when "domain"  then domain_matches?(id.value)
      when "subject" then @subject.include?(fold(id.value))
      when "header"  then header_matches?(id.value)
      else false
      end
    end

    def keyword_score(id, source)
      value = id.value.to_s
      if value.match?(/\A\d{4}\z/) && value == source.last_four
        return anchored_last_four?(value) ? LAST_FOUR_WEIGHT : 0
      end

      body_contains_word?(value) ? WEIGHTS["keyword"] : 0
    end

    # --- per-kind matchers ----------------------------------------------------

    def sender_matches?(value)
      return false if from_email.blank?

      if value.to_s.include?("@")
        fold(from_email) == fold(value)
      else
        fold(@from).include?(fold(value))
      end
    end

    def domain_matches?(value)
      return false if from_email.blank?

      domain = fold(from_email).split("@").last
      domain == fold(value) || domain.end_with?(".#{fold(value)}")
    end

    def header_matches?(value)
      name, expected = value.to_s.split(":", 2)
      return false if name.blank? || expected.to_s.strip.empty?

      target = @headers.find { |h| h["name"].to_s.casecmp(name.strip).zero? }
      target && fold(target["value"]).include?(fold(expected.strip))
    end

    def body_contains_word?(value)
      escaped = Regexp.escape(fold(value))
      @body.match?(/(?:\A|[^a-z0-9])#{escaped}(?:\z|[^a-z0-9])/)
    end

    def anchored_last_four?(value)
      escaped = Regexp.escape(value)
      return true if digit_runs.any? { |run| run.length > 4 && run.end_with?(value) }
      return true if @body.match?(/#{MASK_PREFIX.source}#{escaped}(?!\d)/)
      return true if @body.match?(/(?:#{TERMINATION_PHRASE.source})\s+#{escaped}(?!\d)/)

      false
    end

    def digit_runs
      @digit_runs ||= @body.scan(/\d+/)
    end

    def from_email
      @from_email ||= @from[/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/]
    end

    # Case-insensitive + accent-folded comparison form ("Clásica" ~ "clasica").
    def fold(text)
      text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").downcase
    end
  end
end
