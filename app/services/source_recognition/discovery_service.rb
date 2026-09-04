# frozen_string_literal: true

module SourceRecognition
  # DiscoveryService
  # Gmail-based automatic discovery for Source Recognition. Processes one
  # fetched email at a time (cheap, deterministic — no AI):
  #
  #   1. FinancialEmailFilter decides whether the email is a likely financial
  #      notification and which institution it belongs to.
  #   2. The user's existing Money Sources determine which source(s) the
  #      email likely belongs to: confirmed recognition rules first
  #      (SourceRecognition::Matcher), then institution-level candidates.
  #   3. Discovered values (sender, domain, subject, identification keywords)
  #      are persisted as SUGGESTIONS (status "suggested", origin "gmail").
  #      Confirmed values are never touched, duplicates never created.
  #
  # The user reviews the suggestions on the recognition page and confirms
  # them; only then do they participate in matching.
  class DiscoveryService
    # Upper bound per kind per source to bound noise from messy mailboxes.
    MAX_PER_KIND = 8

    Result = Struct.new(:passed?, :institution, :suggestions_created,
                        :candidate_source_ids, keyword_init: true)

    class << self
      def call(user:, message:)
        new(user).process(message)
      end
    end

    def initialize(user)
      @user = user
    end

    def process(message)
      return empty_result unless has_sources?

      filter_result = FinancialEmailFilter.call(message)
      return empty_result unless filter_result.passed?

      candidates = candidate_sources(message, filter_result.institution)
      return empty_result if candidates.empty?

      created = candidates.sum { |source| suggest_for(source, message, filter_result) }

      Result.new(passed?: true, institution: filter_result.institution,
                 suggestions_created: created, candidate_source_ids: candidates.map(&:id))
    end

    private

    attr_reader :user

    def has_sources?
      @has_sources ||= user.money_sources.exists?
    end

    def empty_result
      Result.new(passed?: false, institution: nil, suggestions_created: 0, candidate_source_ids: [])
    end

    # Which of the user's sources does this email likely belong to?
    # 1. Confirmed recognition rules with a single winner → that source.
    # 2. Ambiguous recognition (several tied sources, same institution) →
    #    all of them (institution-level values are safe for each).
    # 3. No confirmed match → sources of the discovered institution.
    def candidate_sources(message, institution)
      matched = Matcher.call(user: user, message: message)
      return [ matched ] if matched.is_a?(MoneySource)
      return matched if matched.is_a?(Array)

      return [] unless institution

      user.money_sources.includes(recognition: :recognition_identifiers)
          .select { |source| institution_matches_source?(institution, source) }
    end

    # A source belongs to the institution when its bank (folded) equals one
    # of the institution's aliases, or its name contains one.
    def institution_matches_source?(institution, source)
      bank = TextNormalizer.fold(source.institution)
      name = TextNormalizer.fold(source.name)
      institution.folded_aliases.any? do |alias_word|
        bank == alias_word || name.include?(alias_word)
      end
    end

    # --- suggestion building --------------------------------------------------

    def suggest_for(source, message, filter_result)
      created = 0
      email = from_email(message)
      domain = email && email.split("@").last

      # Institution-level values (senders, domains, subject templates) are
      # safe to reuse across every source of the same institution.
      created += suggest!(source, :sender, email)
      created += suggest!(source, :domain, domain)

      if subject_usable?(message, filter_result)
        created += suggest!(source, :subject, clean_subject(message[:subject]))
      end

      # Identification keywords are PRODUCT-specific: only suggest tokens
      # that actually identify THIS source.
      keyword_candidates(source, message, filter_result).each do |value|
        created += suggest!(source, :keyword, value)
      end
      created
    end

    def from_email(message)
      message[:from].to_s[/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/]
    end

    def subject_usable?(message, filter_result)
      subject = TextNormalizer.fold(message[:subject])
      return false if subject.blank?

      institution = filter_result.institution
      alias_present = institution && Catalog.matched_alias(subject, institution)
      alias_present.present? || filter_result.subject_patterns.any?
    end

    # Strips reply/forward prefixes and collapses whitespace so recurring
    # templates collapse to a single value.
    def clean_subject(subject)
      subject.to_s.gsub(/\A\s*((re|fwd?|fw)\s*:\s*)+/i, "").gsub(/\s+/, " ").strip
    end

    # Deterministic keyword candidates for a source:
    #   - the institution alias actually present in the email (institution-
    #     level token, e.g. "davibank" — shared by all sources of the bank),
    #   - product tokens from THIS source's name present in the email body
    #     (e.g. "clasica" for "Davibank Clásica" — never copied elsewhere),
    #   - the source's last four digits when anchored in the body.
    def keyword_candidates(source, message, filter_result)
      body = TextNormalizer.fold(message[:body_text])
      subject = TextNormalizer.fold(message[:subject])
      full_text = "#{subject} #{body}"
      values = []

      alias_matched = filter_result.institution &&
                      Catalog.matched_alias(full_text, filter_result.institution)
      values << alias_matched if alias_matched

      values.concat product_tokens_in(source, full_text)

      last_four = source.last_four
      values << last_four if last_four && Matcher.last_four_in_body?(message[:body_text], last_four)

      values.uniq
    end

    def product_tokens_in(source, full_text)
      bank_tokens = TextNormalizer.fold(source.bank.to_s).split(/\s+/).to_set
      TextNormalizer.fold(source.name.to_s).split(/\s+/)
                    .reject { |token| token.length < 3 || bank_tokens.include?(token) }
                    .reject { |token| SuggestionEngine::STOP_KEYWORDS.include?(token) }
                    .select { |token| TextNormalizer.contains_word?(full_text, token) }
                    .uniq
    end

    # Persists one discovered value as a suggestion. Never overwrites a
    # confirmed value and never creates duplicates: an existing confirmed
    # identifier stops the suggestion; an existing suggested one just gains
    # an observation (recurring signal).
    def suggest!(source, kind, value)
      return 0 if value.blank?

      value = value.to_s.strip
      value = value.downcase unless kind == :subject
      return 0 if value.blank?

      recognition = source.ensure_recognition
      recognition.save! if recognition.new_record?
      identifier = recognition.recognition_identifiers.find_by(kind: kind, value: value)

      if identifier
        if identifier.suggested?
          identifier.update!(observation_count: identifier.observation_count + 1, last_seen_at: Time.current)
        end
        return 0
      end

      return 0 if recognition.recognition_identifiers.where(kind: kind).count >= MAX_PER_KIND

      recognition.recognition_identifiers.create!(
        kind: kind.to_s, value: value, status: "suggested", origin: "gmail",
        position: next_position(recognition, kind), observation_count: 1, last_seen_at: Time.current
      )
      1
    rescue ActiveRecord::RecordNotUnique
      0
    end

    def next_position(recognition, kind)
      recognition.recognition_identifiers.where(kind: kind).maximum(:position).to_i + 1
    end
  end
end
