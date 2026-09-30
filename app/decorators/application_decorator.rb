# frozen_string_literal: true

# ApplicationDecorator: hand-rolled presentation wrapper. Decorators wrap a
# single model and expose view-facing methods without polluting the model.
#
#   ExpenseDecorator.new(expense).description_or_fallback
class ApplicationDecorator
  delegate :id, :to_param, to: :object

  def initialize(object)
    @object = object
  end

  def self.decorate(collection)
    collection.map { |record| new(record) }
  end

  attr_reader :object
end
