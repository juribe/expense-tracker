# frozen_string_literal: true

# Bullet detects N+1 queries, unused eager loading and missing counter caches.
# In development it logs and shows alerts but never raises, so a detection
# does not break the page being browsed. Tests enable raising explicitly (see
# test_helper) and the suite keeps Bullet off by default: with parallel workers
# it raised spurious AVOID notifications depending on what ran alongside, and
# the flaky aborts outweighed the signal. Run the suite with BULLET=1 to turn
# it back on.
if defined?(Bullet)
  Rails.application.config.after_initialize do
    next if Rails.env.test? && !ENV.key?("BULLET")

    Bullet.enable = true
    Bullet.raise = false
    Bullet.alert = true
    Bullet.bullet_logger = true
    Bullet.rails_logger = true
    Bullet.unused_eager_loading_enable = true
    Bullet.counter_cache_enable = true

    # Expense and Income lists preload money_source even when the simple
    # tracking mode hides the source column. The eager load is intentional:
    # keeping it avoids per-row queries when the mode is detailed. N+1
    # detection stays enabled. (The dashboard opts out of the preload in
    # simple mode; see Expense.dashboard_summary.)
    %w[Expense Income].each do |class_name|
      Bullet.add_safelist type: :unused_eager_loading,
                          class_name: class_name,
                          association: :money_source
    end

    # The nested credit_account preload belongs to the same intentional source
    # load; simple mode hides it, advanced mode uses it for card last-four.
    Bullet.add_safelist type: :unused_eager_loading,
                        class_name: "MoneySource",
                        association: :credit_account
  end
end
