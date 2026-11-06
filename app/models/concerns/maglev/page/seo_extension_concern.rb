# frozen_string_literal: true

# Small extension of Maglev CMS v3: adds the canonical_url and meta_robots
# SEO fields to Maglev::Page without modifying the gem's internals. Loaded
# from config/initializers/maglev.rb (see the to_prepare block at the bottom).
module Maglev
  module Page::SeoExtensionConcern
    extend ActiveSupport::Concern

    included do
      translates :canonical_url, :meta_robots
    end

    protected

    # Make sure the two extra fields travel between the draft and the
    # published payloads just like the native SEO fields.
    def published_payload_additional_attributes
      super + %w[canonical_url_translations meta_robots_translations]
    end
  end
end
