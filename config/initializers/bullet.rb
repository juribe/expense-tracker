# frozen_string_literal: true

# Bullet detects N+1 queries, unused eager loading and missing counter caches.
# Available in development; raises on detection so problems surface while
# browsing. In test it stays off: with parallel workers it raised spurious
# AVOID notifications depending on what ran alongside, and the flaky aborts
# outweighed the signal. Run the suite with BULLET=1 to turn it back on.
if defined?(Bullet)
  Rails.application.config.after_initialize do
    next if Rails.env.test? && !ENV.key?("BULLET")

    Bullet.enable = true
    Bullet.raise = true
    Bullet.alert = true
    Bullet.bullet_logger = true
    Bullet.rails_logger = true
    Bullet.unused_eager_loading_enable = true
    Bullet.counter_cache_enable = true
  end
end
