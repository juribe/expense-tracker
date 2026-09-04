# frozen_string_literal: true

module SourceRecognition
  # FinancialEmailFilter
  # Cheap, deterministic first-stage filter. Scores how likely an email is a
  # financial notification BEFORE any expensive (AI) processing:
  #
  #   institution domain match          = strong signal (+3)
  #   institution alias in from/subject = strong signal (+2)
  #   financial keyword in subject      = medium signal (+2 each, capped)
  #   financial keyword in body         = medium signal (+1 each, capped)
  #   financial subject pattern         = medium signal (+2 each, capped)
  #
  # Marketing/promotional wording is rejected outright, and a bank domain
  # alone is NOT enough: the email must also show a transactional signal
  # (subject keyword/pattern, or a money-movement keyword in the body).
  # "Conoce nuestra nueva tarjeta..." therefore never passes.
  #
  #   result = FinancialEmailFilter.call(message)
  #   result.passed?      # → hand the email to recognition/discovery/AI
  #   result.institution  # → FinancialInstitution or nil
  class FinancialEmailFilter
    Result = Struct.new(:passed?, :score, :institution, :alias_matched,
                        :subject_keywords, :body_keywords, :subject_patterns,
                        keyword_init: true)

    PASS_THRESHOLD = 4
    DOMAIN_SCORE = 3
    ALIAS_SCORE = 2
    SUBJECT_KEYWORD_SCORE = 2
    BODY_KEYWORD_SCORE = 1
    PATTERN_SCORE = 2
    SUBJECT_KEYWORD_CAP = 4
    BODY_KEYWORD_CAP = 3
    PATTERN_CAP = 4

    # Marketing / promotional wording — checked on FOLDED text (no accents).
    MARKETING_PATTERN = /promocion\b|descuento\b|oferta exclusiva|%(\s|\u00a0)*off|newsletter|marketing|rebaja\b|cupon\b|coupon\b|promo\b|registrate\b|abre tu cuenta/i.freeze

    class << self
      def call(message)
        new.call(message)
      end
    end

    def initialize(catalog: Catalog)
      @institutions = catalog.institutions
      @domain_index = catalog.domains_index(@institutions)
      @keywords = catalog.keywords
      @patterns = catalog.subject_patterns
    end

    def call(message)
      subject = TextNormalizer.fold(message[:subject])
      body = TextNormalizer.fold(message[:body_text])
      full_text = "#{subject} #{body}"

      return reject if marketing?(full_text)

      domain_institution = Catalog.match_domain(from_domain(message), @domain_index)
      institution = domain_institution || matched_alias_any(full_text)
      alias_matched = institution && Catalog.matched_alias(full_text, institution)

      subject_hits = boundary_hits(subject, @keywords)
      body_hits = boundary_hits(body, @keywords)
      pattern_hits = boundary_hits(subject, @patterns)

      score = [ DOMAIN_SCORE * (domain_institution ? 1 : 0), ALIAS_SCORE * (alias_matched ? 1 : 0),
                [ subject_hits.length * SUBJECT_KEYWORD_SCORE, SUBJECT_KEYWORD_CAP ].min,
                [ body_hits.length * BODY_KEYWORD_SCORE, BODY_KEYWORD_CAP ].min,
                [ pattern_hits.length * PATTERN_SCORE, PATTERN_CAP ].min ].sum

      transactional = subject_hits.any?(&:transactional?) ||
                      body_hits.any?(&:transactional?) ||
                      pattern_hits.any?

      Result.new(
        passed?: score >= PASS_THRESHOLD && transactional,
        score: score, institution: institution, alias_matched: alias_matched,
        subject_keywords: subject_hits, body_keywords: body_hits, subject_patterns: pattern_hits
      )
    end

    private

    def reject
      Result.new(passed?: false, score: 0, institution: nil, alias_matched: nil,
                 subject_keywords: [], body_keywords: [], subject_patterns: [])
    end

    def marketing?(folded_text)
      folded_text.match?(MARKETING_PATTERN)
    end

    def from_domain(message)
      email = message[:from].to_s[/[\w.+-]+@[\w-]+(?:\.[\w-]+)+/]
      email&.split("@")&.last
    end

    def matched_alias_any(folded_text)
      match = @institutions.filter_map do |institution|
        found = Catalog.matched_alias(folded_text, institution)
        [ found, institution ] if found
      end.max_by { |alias_word, _| alias_word.length }
      match && match.last
    end

    # Distinct catalog entries whose value appears in the text respecting
    # word boundaries.
    def boundary_hits(folded_text, entries)
      return [] if folded_text.blank?

      entries.select { |entry| TextNormalizer.contains_word?(folded_text, entry.value) }
    end
  end
end
