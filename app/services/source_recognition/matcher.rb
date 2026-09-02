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
  #   Matcher.call(user: user, message: gmail_message_hash)
  #     => MoneySource            when exactly one source wins
  #     => [MoneySource, ...]     when the top score is tied (ambiguous)
  #     => nil                    when nothing matches
  class Matcher
    WEIGHTS = { "sender" => 3, "domain" => 3, "subject" => 2, "header" => 2, "keyword" => 1 }.freeze
    LAST_FOUR_WEIGHT = 4
    MASK_PREFIX = /[*•#]+\s*/.freeze
    TERMINATION_PHRASE = /terminad[ao]s?\s+en|termina(?:n|do)?\s+en\s+los?\s+d[ií]gitos|termina\s+en|ending\s+in/.freeze

    def self.call(user:, message:)
      new(user: user, message: message).call
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
        [source, score] if score.positive?
      end
      return nil if scored.empty?
      return scored.first.first if scored.one?

      ranked = scored.sort_by { |_, score| -score }
      return ranked.first.first if ranked.first.last > ranked.second.last

      ranked.map(&:first)
    end

    private

    def sources
      @sources ||= @user.money_sources
                        .includes(recognition: :recognition_identifiers)
                        .select(&:recognition_configured?)
    end

    def score_for(source)
      source.recognition_identifiers.sum { |id| identifier_score(id, source) }
    end

    def identifier_score(id, source)
      case id.kind
      when "sender"  then sender_matches?(id.value) ? WEIGHTS["sender"] : 0
      when "domain"  then domain_matches?(id.value) ? WEIGHTS["domain"] : 0
      when "subject" then @subject.include?(fold(id.value)) ? WEIGHTS["subject"] : 0
      when "header"  then header_matches?(id.value) ? WEIGHTS["header"] : 0
      when "keyword" then keyword_score(id, source)
      else 0
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
