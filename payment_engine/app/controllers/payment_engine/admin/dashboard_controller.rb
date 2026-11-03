# frozen_string_literal: true

module PaymentEngine
  module Admin
    class DashboardController < BaseController
      def index
        @charged_income = Payment.where(status: "succeeded").sum(:amount)
        @successful_payments = Payment.where(status: "succeeded").count
        @failed_payments = Payment.where(status: "failed").count
        @active_memberships = Membership.where(status: "active").count
        @active_subscriptions = Subscription.where(status: "active").count
        @upcoming_renewals = Subscription.where(status: "active").where("next_billing_at <= ?", 7.days.from_now).count

        @recent_purchases = Purchase.includes(:owner, :payment_option).order(created_at: :desc).limit(10)
        @recent_payments = Payment.includes(:purchase).order(created_at: :desc).limit(10)
        @recent_memberships = Membership.includes(:owner, :membership_type).order(created_at: :desc).limit(10)
        @cancelled_subscriptions = Subscription.includes(:owner, :payment_option).where(status: "cancelled").order(updated_at: :desc).limit(10)
        @failed_webhooks = WebhookEvent.where(status: "failed").order(created_at: :desc).limit(10)

        @providers_unconfigured = Provider.where(active: true).select { |p| !p.configured? }
      end
    end
  end
end
