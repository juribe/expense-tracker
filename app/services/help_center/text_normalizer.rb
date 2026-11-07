# HelpCenter::TextNormalizer
# Produces the lowercase, accent-free text used by search and ranking.
#
# Example: HelpCenter::TextNormalizer.call("<p>Cómo registrar un gasto</p>")
#          # => "como registrar un gasto"
class HelpCenter::TextNormalizer
  def self.call(text)
    new(text).call
  end

  def initialize(text)
    @text = text
  end

  def call
    return "" if @text.blank?

    plain = ActionView::Base.full_sanitizer.sanitize(@text.to_s)
    ActiveSupport::Inflector.transliterate(plain)
                              .downcase
                              .gsub(/[^a-z0-9]+/, " ")
                              .squish
  end
end
