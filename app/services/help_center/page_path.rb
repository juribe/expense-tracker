# HelpCenter::PagePath
# Classifies a Maglev page path as the help landing, a category or an article.
#
# Example:
#   HelpCenter::PagePath.new("ayuda/gastos/registrar-gasto").article? # => true
class HelpCenter::PagePath
  ROOT = "ayuda"
  MAX_SEGMENTS = 3
  SLUG_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/

  attr_reader :path

  def initialize(path)
    @path = path.to_s.strip.sub(%r{\A/+}, "").sub(%r{/+\z}, "")
  end

  def segments
    path.split("/")
  end

  def root?
    segments == [ ROOT ]
  end

  def category?
    segments.length == 2 && segments.first == ROOT && valid_slug?(segments.last)
  end

  def article?
    segments.length == MAX_SEGMENTS && segments.first == ROOT &&
      segments.drop(1).all? { |segment| valid_slug?(segment) }
  end

  def valid?
    root? || category? || article?
  end

  def help_center?
    path == ROOT || path.start_with?("#{ROOT}/")
  end

  def category_path
    return path if category?

    segments.first(2).join("/") if article?
  end

  def slug
    segments.last
  end

  def to_s
    path
  end

  private

  def valid_slug?(segment)
    SLUG_PATTERN.match?(segment.to_s)
  end
end
