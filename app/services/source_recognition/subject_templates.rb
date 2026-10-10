# frozen_string_literal: true

module SourceRecognition
  # SubjectTemplates
  # Shared helpers to turn raw email subjects into REUSABLE recognition
  # patterns. An email subject mixes a recurring headline with per-email
  # noise ("Compraste por $50.000 en Tienda X"): amounts, dates and card
  # references never repeat, so the reusable value is a TEMPLATE — everything
  # before the first amount-like run. Subjects without amounts are kept whole
  # when they look like a short recurring headline.
  #
  # Used by SourceRecognition::DiscoveryService (per-source suggestions) and
  # Gmail::SetupScanService (connection-level subject templates), so the two
  # features always agree on what collapses into the same pattern.
  module SubjectTemplates
    AMOUNT_RUN = /\$\s*\d[\d.,]*|\d[\d.,]{3,}|[*•#]+\s*\d{4}/.freeze
    TEMPLATE_MIN_WORDS = 2
    TEMPLATE_MAX_WORDS = 8

    module_function

    # Strips reply/forward prefixes and collapses whitespace so recurring
    # templates collapse to a single value.
    def clean(subject)
      subject.to_s.gsub(/\A\s*((re|fwd?|fw)\s*:\s*)+/i, "").gsub(/\s+/, " ").strip
    end

    # The reusable template for a subject, or nil when the subject cannot
    # collapse into one (too short / too long without any amount anchor).
    def template(subject)
      cleaned = clean(subject)
      return nil if cleaned.blank?

      cut_at = cleaned.index(AMOUNT_RUN)
      headline = cleaned[0, cut_at || cleaned.length].gsub(/\s+/, " ").strip
      words = headline.scan(/\S+/).length
      return nil if words < TEMPLATE_MIN_WORDS
      return nil if cut_at.nil? && words > TEMPLATE_MAX_WORDS

      headline
    end

    # Folded (lowercase, accent-stripped) comparison key so counting and
    # deduplication are accent- and case-insensitive.
    def key(template)
      Catalog.fold(template)
    end
  end
end
