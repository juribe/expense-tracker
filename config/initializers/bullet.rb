# frozen_string_literal: true

# Bullet detects N+1 queries, unused eager loading and missing counter caches.
# Available in development and test; raises on detection so problems surface
# while browsing or running the integration test suite.
if defined?(Bullet)
  Rails.application.config.after_initialize do
    Bullet.enable = true
    Bullet.raise = true
    Bullet.alert = true
    Bullet.bullet_logger = true
    Bullet.rails_logger = true
    Bullet.unused_eager_loading_enable = true
    Bullet.counter_cache_enable = true
  end
end
