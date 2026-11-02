# Host application integration

## 1. Install

```ruby
# Gemfile
gem "payment_engine", path: "engines/payment_engine"
```

```bash
bundle install
bin/rails payment_engine:install:migrations
bin/rails db:migrate
```

```ruby
# config/routes.rb
mount PaymentEngine::Engine => "/payment_engine"
```

```ruby
# config/initializers/payment_engine.rb
PaymentEngine.configure do |config|
  config.default_provider = :epayco
  config.providers = {
    epayco: {
      public_key: ENV["EPAYCO_PUBLIC_KEY"],
      private_key: ENV["EPAYCO_PRIVATE_KEY"],
      customer_id: ENV["EPAYCO_CUSTOMER_ID"],
      p_key: ENV["EPAYCO_P_KEY"],
      confirmation_url: "https://myapp.example/payment_engine/webhooks/epayco"
    }
  }
  config.membership_timezone = "America/Bogota"
  config.expiration_grace_period_days = 3
end
```

The host model does not need new columns:

```ruby
class User < ApplicationRecord
  has_many :memberships, as: :owner, class_name: "PaymentEngine::Membership"
  has_many :purchases,   as: :owner, class_name: "PaymentEngine::Purchase"
end
```

## 2. Seed catalog

```ruby
premium = PaymentEngine::MembershipType.find_or_create_by!(slug: "premium") do |type|
  type.name = "Premium"
  type.description = "Unlimited access"
end

PaymentEngine::PaymentOption.find_or_create_by!(slug: "premium-monthly") do |option|
  option.membership_type = premium
  option.name = "Premium monthly"
  option.price = 19_900
  option.currency = "COP"
  option.billing_type = "one_time"
  option.interval = "month"
  option.interval_count = 1
  option.sort_order = 1
end

PaymentEngine::PaymentOption.find_or_create_by!(slug: "premium-monthly-auto") do |option|
  option.membership_type = premium
  option.name = "Premium monthly (automatic)"
  option.price = 19_900
  option.currency = "COP"
  option.billing_type = "recurring"
  option.interval = "month"
  option.interval_count = 1
  option.sort_order = 2
end
```

## 3. Check access

```ruby
# app/controllers/concerns/premium_access.rb
module PremiumAccess
  extend ActiveSupport::Concern

  def require_premium!
    return if PaymentEngine::Membership.active?(current_user, type: "premium")

    redirect_to pricing_path, alert: "A Premium membership is required."
  end
end
```

```erb
<% if PaymentEngine::Membership.active?(current_user, type: "premium") %>
  <span class="badge text-bg-success">Premium</span>
<% end %>
```

Show the renewal state:

```ruby
membership = PaymentEngine::Membership.current(current_user, type: "premium")
membership&.days_remaining
membership&.expiring_soon?(days: 7)
membership&.subscription&.cancel_at_period_end?
```

## 4. Checkout

```ruby
# app/controllers/checkouts_controller.rb
class CheckoutsController < ApplicationController
  before_action :authenticate_user!

  def create
    option = PaymentEngine::PaymentOption.find_by_slug(params[:payment_option_slug])
    return redirect_to pricing_path, alert: "Option not available" unless option

    result = PaymentEngine::Purchases::Create.call(
      owner: current_user,
      payment_option: option,
      provider: :epayco
    )

    if result.success?
      checkout = result.data[:checkout]
      redirect_to checkout[:url], allow_other_host: true
    else
      redirect_to pricing_path, alert: result.error_message
    end
  end
end
```

Never activate access in this controller. The provider confirmation arrives at
`POST /payment_engine/webhooks/:provider` and the engine activates or extends the membership.

## 5. Prices and options

```ruby
PaymentEngine::PaymentOption.for("premium").each do |option|
  # option.price is an integer in whole currency units (19900 for $19.900 COP)
end
```

Do not recalculate prices in the host. The engine snapshots the price on the purchase and verifies
provider amounts against it.

## 6. Subscriptions

```ruby
subscription = PaymentEngine::Subscriptions::Current.call(owner: current_user).data

PaymentEngine::Subscriptions::Cancel.call(subscription, immediately: false)
# Access remains until current_period_ends_at.
```

The host never talks to ePayco directly and never changes internal statuses.

## 7. Schedule maintenance

```ruby
# config/recurring.yml (Solid Queue) or your scheduler
payment_engine_expiration:
  command: "bin/rails payment_engine:expire_memberships"
  schedule: every day at 3am
```

or from a host job/cron:

```ruby
PaymentEngine::Jobs::ExpireMembershipsJob.perform_later
```

## 8. React to engine events

```ruby
# config/initializers/payment_engine.rb
PaymentEngine.on(:membership_activated) do |event|
  UserNotifier.membership_activated(event[:membership].owner).deliver_later
end

PaymentEngine.on(:subscription_payment_failed) do |event|
  DunningMailer.payment_failed(event[:subscription]).deliver_later
end
```

Callbacks run after commit and are isolated from the financial transaction.

## 9. Yogasto example

```ruby
# Access
PaymentEngine::Membership.active?(current_user, type: "premium")

membership = PaymentEngine::Membership.current(current_user, type: "premium")
membership.days_remaining
membership.expires_at
membership.expiring_soon?(days: 7)

# Options
PaymentEngine::PaymentOption.for("premium")

# Purchase
result = PaymentEngine::Purchases::Create.call(
  owner: current_user,
  payment_option: PaymentEngine::PaymentOption.find_by_slug("premium-monthly"),
  provider: :epayco
)

# Cancellation
PaymentEngine::Subscriptions::Cancel.call(
  PaymentEngine::Subscriptions::Current.call(owner: current_user).data,
  immediately: false
)
```

Yogasto does not implement ePayco logic, expiration logic, webhook processing or renewal
calculation. It only consumes this API.
