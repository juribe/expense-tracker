module PaymentEngine
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
    self.table_name_prefix = "payment_engine_"
  end
end
