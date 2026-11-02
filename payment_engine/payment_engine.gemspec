require_relative "lib/payment_engine/version"

Gem::Specification.new do |spec|
  spec.name        = "payment_engine"
  spec.version     = PaymentEngine::VERSION
  spec.authors     = [ "Yogasto" ]
  spec.email       = [ "dev@example.com" ]
  spec.homepage    = "https://example.com"
  spec.summary     = "PaymentEngine Rails Engine"
  spec.description = "Reusable payment engine for Rails applications."
  spec.license     = "MIT"

  spec.metadata["allowed_push_host"] = "https://example.com"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://example.com"
  spec.metadata["changelog_uri"] = "https://example.com"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 8.1.0"
  spec.add_dependency "will_paginate", "~> 4.0"
end
