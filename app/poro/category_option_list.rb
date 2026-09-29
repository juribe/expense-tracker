# frozen_string_literal: true

# CategoryOptionList
# The categories the picker offers: defaults and the user's own share one
# list, ordered alphabetically. The accent-folded name is the sort key so
# "Árbol" lands next to "Arroz" instead of after "Zapatos".
#
# Example: CategoryOptionList.new(categories).options
class CategoryOptionList
  def initialize(categories)
    @categories = categories.to_a
  end

  def options
    @options ||= categories
                 .sort_by { |category| CategoryOption.normalize_search(category.name) }
                 .map { |category| CategoryOption.new(category) }
  end

  private

  attr_reader :categories
end
