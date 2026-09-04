# frozen_string_literal: true

module SourceRecognition
  # TextNormalizer
  # Case-insensitive + accent-folded comparison helpers shared by the cheap
  # financial email filter and the discovery service.
  #
  #   TextNormalizer.fold("Transacción")  => "transaccion"
  #   TextNormalizer.fold("Clásica")      => "clasica"
  module TextNormalizer
    module_function

    # Lowercase, strip accents (NFKD + drop marks), collapse whitespace.
    # Tolerates ASCII-8BIT / binary input by coercing to UTF-8 first so the
    # NFKD normalization can never raise a CompatibilityError.
    def fold(text)
      text.to_s.dup.force_encoding(Encoding::UTF_8)
          .unicode_normalize(:nfkd)
          .gsub(/\p{Mn}/, "")
          .gsub(/\s+/, " ")
          .strip
          .downcase
    end

    # True when `value` appears in `text` respecting word boundaries
    # ("clásica" matches "tarjeta Clasica," but not "clasicasur").
    def contains_word?(text, value)
      escaped = Regexp.escape(fold(value))
      fold(text).match?(boundary_regex(escaped))
    end

    def boundary_regex(escaped_value)
      /(?:\A|[^a-z0-9])#{escaped_value}(?:\z|[^a-z0-9])/
    end
  end
end
