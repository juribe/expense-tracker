module PaymentEngine
  module Subscriptions
    # Returns the renewal agreement associated with the owner's current
    # membership, if any.
    class Current
      def self.call(owner = nil, **options)
        owner ||= options[:owner]
        membership = Membership.current(owner)
        Result.success(data: membership&.subscription)
      end
    end
  end
end
