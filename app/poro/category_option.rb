# frozen_string_literal: true

# CategoryOption
# One row of the searchable category picker: the category plus how the
# picker presents and matches it.
#
# Example: CategoryOption.new(category).search_text
class CategoryOption
  attr_reader :category

  def initialize(category)
    @category = category
  end

  def id
    category.id
  end

  def name
    category.name
  end

  def slug
    category.slug
  end

  def label
    name
  end

  # Accent-, case- and punctuation-insensitive version of the name, matching
  # the picker's javascript normalization character for character. It must
  # NOT reuse ActivityClassification.normalize_name: that one drops merchant
  # suffixes ("Netflix-99123" -> "netflix"), which would make a category the
  # user can see impossible to find by typing its own name.
  def search_text
    self.class.normalize_search(name)
  end

  def self.normalize_search(text)
    text.to_s.unicode_normalize(:nfd)
        .gsub(/[\u0300-\u036f]/, "")
        .downcase
        .gsub(/[^\p{L}\p{N}\s]/u, " ")
        .squish
  end
end
