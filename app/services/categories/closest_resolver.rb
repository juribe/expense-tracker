# frozen_string_literal: true

module Categories
  # Resolves a free-form category name (typically produced by AI extraction) to
  # one of the user's existing categories, or returns nil when it is a genuinely
  # NEW category that does not exist yet.
  #
  # Resolution order:
  #   1. exact normalized name match (accent/case insensitive)
  #   2. stored knowledge: ActivityClassification for the activity/description
  #      (a user correction always wins, so repeated messages stop flip-flopping)
  #   3. English seed -> Spanish alias
  #   4. curated variant map (near-identical renames of existing categories)
  #   5. similarity (token Jaccard / containment) above a threshold
  #
  # Steps 4-5 never create a near-duplicate category: the variant name is folded
  # into the existing one. Every similarity fold is recorded back through
  # ActivityClassification (source: "rule") when record: true, so the fold is
  # reviewable and queryable instead of being a silent one-off decision.
  #
  #   Categories::ClosestResolver.call(user: user, name: "Mantenimiento del apartamento")
  #   # => #<struct Result category=#<Category...>, matched_by=:variant, similarity=1.0>
  class ClosestResolver
    Result = Struct.new(:category, :matched_by, :similarity, keyword_init: true) do
      def matched?
        category.present?
      end
    end

    # English seed names that exist in the category tree are folded into their
    # Spanish equivalents so a resolved category always uses the Spanish label.
    ALIASES = {
      "entertainment" => "Entretenimiento", "shopping" => "Compras",
      "restaurants" => "Comida y restaurantes", "groceries" => "Compras",
      "health" => "Salud", "transportation" => "Transporte", "travel" => "Viajes",
      "utilities" => "Servicios públicos", "others" => "Otros", "other" => "Otros",
      "housing" => "Vivienda", "education" => "Educación", "clothing" => "Compras",
      "parking" => "Transporte", "gasoline" => "Transporte", "fuel" => "Transporte",
      "pet care" => "Otros", "pets" => "Otros", "subscriptions" => "Otros",
      "subscription" => "Otros", "market" => "Compras"
    }.freeze

    # Curated "very close" variants -> canonical category name. AI labels you
    # keep seeing that differ only in wording from an existing category go here,
    # so the fold is deterministic and never spawns a duplicate category. Keys
    # are matched against BOTH the extracted category name and the activity,
    # so a strong brand signal ("netflix") always wins over a generic/wrong AI
    # category while an explicit user mapping still takes precedence.
    VARIANTS = {
      "netflix" => "Entretenimiento",
      "pago de netflix" => "Entretenimiento",
      "gasto de netflix" => "Entretenimiento",
      "pago netflix" => "Entretenimiento",
      "suscripcion netflix" => "Entretenimiento",
      "netflix mensual" => "Entretenimiento",
      "restaurante (rappi)" => "Comida y restaurantes",
      "restaurante rappi" => "Comida y restaurantes",
      "mantenimiento del apartamento" => "Vivienda"
    }.freeze

    # Minimum shared-token coverage for the similarity fold.
    SIMILARITY_THRESHOLD = 0.5

    def self.call(user:, name:, activity: nil, record: true)
      new(user: user, name: name, activity: activity, record: record).resolve
    end

    attr_reader :user, :name, :activity

    def initialize(user:, name:, activity: nil, record: true)
      @user = user
      @name = name.to_s.strip
      @activity = activity.to_s.strip.presence
      @record = record
    end

    def resolve
      return Result.new(category: nil, matched_by: nil) if name.blank?

      categories = Category.for_user(user).to_a
      return Result.new(category: nil, matched_by: nil) if categories.empty?

      result =
        if ALIASES.key?(normalize(name))
          # English seed input: fold into the Spanish equivalent when it exists;
          # otherwise fall back to exact resolution (the English category itself).
          alias_match(categories) || exact_match(categories)
        else
          # Explicit user knowledge for the activity wins first; then a strong
          # curated brand/activity variant (Netflix -> Entretenimiento) beats an
          # exact-but-generic AI category name; then exact/variant/similar.
          learned_match ||
            activity_variant_match(categories) ||
            exact_match(categories) ||
            variant_match(categories) ||
            similar_match(categories)
        end
      record_fold!(result) if result&.matched_by == :similar
      result || Result.new(category: nil, matched_by: nil)
    end

    private

    def exact_match(categories)
      hit = categories.find { |category| normalize(category.name) == normalize(name) }
      return Result.new(category: hit, matched_by: :exact, similarity: 1.0) if hit
    end

    def learned_match
      return nil if activity.blank?

      classification = ActivityClassification.lookup(user: user, name: activity)
      return nil unless classification&.category

      Result.new(category: classification.category, matched_by: :learned, similarity: 1.0)
    end

    def alias_match(categories)
      target = ALIASES[normalize(name)]
      return nil if target.nil?

      hit = categories.find { |category| normalize(category.name) == normalize(target) }
      return Result.new(category: hit, matched_by: :alias, similarity: 1.0) if hit
    end

    def variant_match(categories)
      target = VARIANTS[normalize(name)]
      return nil if target.nil?

      hit = categories.find { |category| normalize(category.name) == normalize(target) }
      return Result.new(category: hit, matched_by: :variant, similarity: 1.0) if hit
    end

    # The extracted category name can be a generic one that happens to exist
    # ("Servicios públicos") while the ACTIVITY is a known curated brand
    # ("netflix"). Folding by activity corrects the AI here without ever
    # consulting the (possibly wrong) category name.
    def activity_variant_match(categories)
      return nil if activity.blank?

      target = VARIANTS[normalize(activity)]
      return nil if target.nil?

      hit = categories.find { |category| normalize(category.name) == normalize(target) }
      return Result.new(category: hit, matched_by: :variant, similarity: 1.0) if hit
    end

    def similar_match(categories)
      tokens = word_tokens(normalize(name))
      return nil if tokens.empty?

      best = categories.each_with_object([]) do |category, acc|
        candidate_tokens = word_tokens(normalize(category.name))
        next if candidate_tokens.empty?

        score = overlap_score(tokens, candidate_tokens)
        acc << [ score, category ] if score >= SIMILARITY_THRESHOLD
      end
      return nil if best.empty?

      score, category = best.max_by { |entry| [ entry[0], entry[1].name.length ] }
      return nil if category.nil?

      Result.new(category: category, matched_by: :similar, similarity: score.round(3))
    end

    def overlap_score(tokens, candidate_tokens)
      shared = tokens & candidate_tokens
      return 0.0 if shared.empty?

      union_size = (tokens | candidate_tokens).size
      jaccard = shared.size.to_f / union_size
      containment = shared.size.to_f / [ tokens.size, candidate_tokens.size ].min
      [ jaccard, containment ].max
    end

    def record_fold!(result)
      return unless @record && activity.present?

      ActivityClassification.record!(
        user: user,
        name: activity,
        category: result.category,
        source: "rule"
      )
    rescue ActiveRecord::RecordInvalid, ArgumentError
      nil
    end

    def normalize(text)
      ActivityClassification.normalize_name(text)
    end

    def word_tokens(text)
      text.to_s.split
    end
  end
end