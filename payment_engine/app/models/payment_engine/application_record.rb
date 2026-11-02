# frozen_string_literal: true

module PaymentEngine
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end
