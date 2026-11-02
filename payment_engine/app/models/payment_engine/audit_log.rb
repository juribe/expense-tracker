# frozen_string_literal: true

module PaymentEngine
  class AuditLog < ApplicationRecord
    self.table_name = "payment_engine_audit_logs"

    def self.dangerous_attribute_method?(name)
      return false if name.to_s == "changes"
      super
    end
  end
end
