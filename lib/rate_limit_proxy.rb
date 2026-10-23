# RateLimitProxy
# Cache proxy for the Rails 8 controller rate limiter: it resolves
# Rails.cache on every call instead of capturing the store instance at
# boot time, so environments that swap the store at runtime (tests stub
# a counting store) and production (Solid Cache) both work.
class RateLimitProxy
  def increment(cache_key, amount, **options)
    Rails.cache.increment(cache_key, amount, **options)
  end
end
