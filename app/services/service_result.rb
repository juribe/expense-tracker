# frozen_string_literal: true

class ServiceResult
  attr_reader :result, :errors

  def initialize(result: nil, errors: [])
    @result = result
    @errors = Array(errors)
  end

  def self.success(result)
    new(result: result)
  end

  def self.error(errors)
    new(errors: errors)
  end

  def success?
    errors.empty?
  end

  def failure?
    !success?
  end
end
