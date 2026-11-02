# frozen_string_literal: true

module PaymentEngine
  class ExpireMembershipsJob < ActiveJob::Base
    def perform
      PaymentEngine::Membership.where(status: "active").where("expires_at < ?", Time.current).find_each do |m|
        m.update!(status: "expired")
      end
    end
  end
end
