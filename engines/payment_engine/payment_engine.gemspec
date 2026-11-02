require_relative "lib/payment_engine/version"

Gem::Specification.new do |spec|
  spec.name        = "payment_engine"
  spec.version     = PaymentEngine::VERSION
  spec.authors     = [ "PaymentEngine contributors" ]
  spec.email       = [ "dev@example.com" ]
  spec.homepage    = "https://example.com/payment_engine"
  spec.summary     = "Reusable Rails engine for memberships, payments and subscriptions."
  spec.description = "PaymentEngine provides membership types, payment options, purchases, payments, " \
                     "recurring subscriptions, payment provider adapters, webhooks and expiration jobs " \
                     "without depending on the host application's domain models."
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,docs,lib}/**/*", "CHANGELOG.md", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.required_ruby_version = ">= 3.1"

  spec.add_dependency "rails", ">= 7.2", "< 9.0"

  spec.add_development_dependency "pg", ">= 1.1"
end
