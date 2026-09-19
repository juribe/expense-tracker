module Categories
  class HeuristicResolver
    SUGGESTION_STOP_WORDS = %w[
      pague pago gasto gaste pagar compre compro gastamos solo en de del al la
      las los un una unos unas que con para por y o a tambien fueron me mi era
      son es mil lucas pesos
    ].freeze

    NON_UTILITY_DIGITAL_TERMS = %w[
      netflix spotify disney canva chatgpt openai microsoft adobe icloud
      dropbox google-one prime hbo max paramount crunchyroll youtube
    ].freeze

    STREAMING_TERMS = %w[
      netflix spotify disney hbo max paramount crunchyroll youtube
    ].freeze

    PARKING_TERMS = %w[
      parking parqueadero parqueo estacionamiento
    ].freeze

    def self.call(user:, name:, activity: nil, record: true)
      new(
        user: user,
        name: name,
        activity: activity,
        record: record
      ).call
    end

    attr_reader :user, :name, :activity

    def initialize(user:, name:, activity: nil, record: true)
      @user = user
      @name = name.to_s.strip
      @activity = activity.to_s.strip.presence
      @record = record
    end

    def call
      resolve_category(
        name,
        nil,
        activity: activity
      )
    end

    # Category resolution is centralized in Categories::ClosestResolver:
    # exact normalized name, learned activity mappings (ActivityClassification),
    # English -> Spanish aliases and a similarity fold.
    def resolve_category(category_name, category_id, activity: nil)
      categories = Category.for_user(user)
      @category_resolution = nil
      @rejected_category_name = false

      resolved =
        if category_id.present?
          categories.find_by(id: category_id)
        elsif category_name.present? || activity.present?
          @category_resolution = Categories::ClosestResolver.call(
            user: user,
            name: category_name.to_s,
            activity: activity,
            record: false
          )

          @category_resolution.category
        end

      apply_business_guards(
        resolved,
        category_name,
        activity,
        categories
      )
    end

    def apply_business_guards(resolved, category_name, activity, categories)
      text = [ category_name, activity ].compact.join(" ").downcase
      return resolved if text.blank?

      transporte = categories.find do |category|
        ActivityClassification.normalize_name(category.name) == "transporte"
      end

      if transporte &&
          PARKING_TERMS.any? { |term| text.include?(term) }
        @category_resolution =
          Categories::ClosestResolver::Result.new(
            category: transporte,
            matched_by: :parking,
            similarity: 1.0
          )

        return transporte
      end

      utilities = categories.find do |category|
        ActivityClassification.normalize_name(category.name) == "servicios publicos"
      end

      if utilities &&
          resolved&.id == utilities.id &&
          NON_UTILITY_DIGITAL_TERMS.any? { |term| text.include?(term) }
        @rejected_category_name = true
        @category_resolution = nil
        return nil
      end

      resolved
    end

    # Builds a short, name-like NEW category from an unmatched activity so a
    # blank category never stays empty:
    #   - streaming services (Netflix, Spotify, ...) suggest "Entretenimiento"
    #   - other digital SaaS (Canva, Microsoft 365, ChatGPT, ...) suggest a new
    #     "Suscripciones" category
    #   - anything else falls back to the cleaned, title-cased activity
    # Returns nil only when nothing scannable remains.
    def suggest_category_name(text)
      return nil if text.blank?

      normalized = ActivityClassification.normalize_name(text).to_s
      return "Entretenimiento" if STREAMING_TERMS.any? { |term| normalized.include?(term) }
      if (NON_UTILITY_DIGITAL_TERMS - STREAMING_TERMS).any? { |term| normalized.include?(term) }
        return "Suscripciones"
      end

      tokens = normalized.split.reject do |token|
        SUGGESTION_STOP_WORDS.include?(token) || token.match?(/\A\d+\z/)
      end
      title = tokens.join(" ")
      return nil if title.blank?

      title.split.map(&:capitalize).join(" ").truncate(40)
    end
  end
end
