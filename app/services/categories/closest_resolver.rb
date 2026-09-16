# frozen_string_literal: true

module Categories
  # Resolves a free-form category name (typically produced by AI extraction) to
  # one of the user's existing categories, or returns nil when it is a genuinely
  # NEW category that does not exist yet.
  #
  # Resolution order:
  #   1. stored knowledge: ActivityClassification for the activity/description
  #      (a user correction always wins, so repeated messages stop flip-flopping)
  #   2. unconditional parking rule: parkeadero/estacionamiento/parking ->
  #      "Transporte" when the user has it
  #   3. the single unconditional housing rule: house maintenance/upkeep/rent and
  #      condominium fees (excluding utilities) go to "Vivienda" when the user has it
  #   4. exact normalized name match (accent/case insensitive)
  #   5. English seed -> Spanish alias
  #   6. similarity (token Jaccard / containment) above a threshold
  #
  # There are NO other unconditional classification rules: category names are
  # never hard-mapped here. When the extracted category name is blank (AI said
  # "null") the name stays unassigned UNLESS the user has explicit stored
  # knowledge for the activity or the parking/housing rule applies. Every
  # similarity fold is recorded back through ActivityClassification (source: "rule") when
  # record: true, so the fold is reviewable and queryable instead of being a
  # silent one-off decision.
  #
  #   Categories::ClosestResolver.call(user: user, name: "Mantenimiento del apartamento")
  #   # => #<struct Result category=Vivienda, matched_by=:housing> when the user has Vivienda
  class ClosestResolver
    Result = Struct.new(:category, :matched_by, :similarity, keyword_init: true) do
      def matched?
        category.present?
      end
    end

    # English seed names that exist in the category tree are folded into their
    # Spanish equivalents so a resolved category always uses the Spanish label.
    # This is label normalization (not classification), so it is not an
    # unconditional rule: it only rewrites the spelling of a name the model or
    # the heuristic parser already chose.
    ALIASES = {
      "entertainment" => "Entretenimiento", "shopping" => "Compras",
      "restaurants" => [ "Restaurante", "Comida" ], "groceries" => "Compras",
      "comida y restaurantes" => [ "Comida" ],
      "health" => "Salud", "transportation" => "Transporte", "travel" => "Viajes",
      "utilities" => "Servicios públicos", "others" => "Otros", "other" => "Otros",
      "housing" => "Vivienda", "education" => "Educación", "clothing" => "Compras",
      "parking" => "Transporte", "gasoline" => "Transporte", "fuel" => "Transporte",
      "parqueadero" => "Transporte", "estacionamiento" => "Transporte",
      "pet care" => "Otros", "pets" => "Otros", "subscriptions" => "Otros",
      "subscription" => "Otros", "market" => "Compras"
    }.freeze

    # Minimum shared-token coverage for the similarity fold.
    SIMILARITY_THRESHOLD = 0.5

    # House-related words grouped by role. Rent/management fees and house
    # maintenance/upkeep are classified as "Vivienda" (the one unconditional
    # rule); utilities are explicitly excluded so "internet del apartamento"
    # still lands in "Servicios públicos".
    HOUSE_FEES = %w[arriendo alquiler administracion predial condominio].freeze
    HOUSE_UPKEEP = %w[mantenimiento reparacion arreglo remodelacion].freeze
    HOUSE_PLACES = %w[apartamento edificio casa hogar vivienda].freeze
    UTILITY_TERMS = %w[agua luz gas internet telefono celular datos energia electricidad].freeze
    PARKING_TERMS = %w[parking parqueadero parqueo estacionamiento].freeze

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
      categories = Category.for_user(user).to_a
      return Result.new(category: nil, matched_by: nil) if categories.empty?

      if name.blank?
        # No extracted category name: the expense stays unassigned unless the
        # user has explicit stored knowledge for the activity or the
        # parking/housing rule applies. Nothing else is classified by an
        # unconditional rule.
        return Result.new(category: nil, matched_by: nil) if activity.blank?

        learned = learned_match
        return learned if learned

        return parking_match(categories, activity) ||
               housing_match(categories, activity) ||
               Result.new(category: nil, matched_by: nil)
      end

      result =
        if ALIASES.key?(normalize(name))
          # English seed input: fold into the Spanish equivalent when it exists;
          # otherwise fall back to exact resolution (the English category itself).
          learned_match || parking_match(categories, "#{name} #{activity}") ||
            housing_match(categories, "#{name} #{activity}") ||
            alias_match(categories) || exact_match(categories)
        else
          learned_match || parking_match(categories, "#{name} #{activity}") ||
            housing_match(categories, "#{name} #{activity}") ||
            exact_match(categories) || similar_match(categories)
        end
      record_fold!(result) if result&.matched_by == :similar
      result || Result.new(category: nil, matched_by: nil)
    end

    private

    def exact_match(categories)
      hit = categories.find { |category| normalize(category.name) == normalize(name) }
      Result.new(category: hit, matched_by: :exact, similarity: 1.0) if hit
    end

    def learned_match
      return nil if activity.blank?

      classification = ActivityClassification.lookup(user: user, name: activity)
      return nil unless classification&.category

      Result.new(category: classification.category, matched_by: :learned, similarity: 1.0)
    end

    def alias_match(categories)
      Array(ALIASES[normalize(name)]).each do |target|
        hit = categories.find { |category| normalize(category.name) == normalize(target) }
        return Result.new(category: hit, matched_by: :alias, similarity: 1.0) if hit
      end
      nil
    end

    # The single unconditional rule: house rent/management fees, or house
    # maintenance/upkeep (needs a house place word), classify as "Vivienda".
    # Utilities are excluded, so a service bill still resolves exactly.
    def housing_match(categories, text)
      return nil if text.blank?

      housing = categories.find { |category| normalize(category.name) == normalize("Vivienda") }
      return nil unless housing

      tokens = fold_tokens(text)
      return nil if tokens.empty? || (tokens & UTILITY_TERMS).any?

      fees = tokens & HOUSE_FEES
      upkeep = tokens & HOUSE_UPKEEP
      places = tokens & HOUSE_PLACES
      return nil unless fees.any? || (places.any? && upkeep.any?)

      Result.new(category: housing, matched_by: :housing, similarity: 1.0)
    end

    # Unconditional parking rule: parking lot fees (parqueadero, parking,
    # estacionamiento) classify as "Transporte" when the user has that
    # category, mirroring the housing rule above.
    def parking_match(categories, text)
      return nil if text.blank?

      transporte = categories.find { |category| normalize(category.name) == normalize("Transporte") }
      return nil unless transporte

      tokens = fold_tokens(text)
      return nil if tokens.empty?

      Result.new(category: transporte, matched_by: :parking, similarity: 1.0) if (tokens & PARKING_TERMS).any?
    end

    def similar_match(categories)
      tokens = fold_tokens(name)
      return nil if tokens.empty?

      best = categories.each_with_object([]) do |category, acc|
        candidate_tokens = fold_tokens(category.name)
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
      shared = tokens.select { |token| candidate_tokens.any? { |candidate| token_close?(token, candidate) } }
      return 0.0 if shared.empty?

      union_size = (tokens | candidate_tokens).size
      jaccard = shared.size.to_f / union_size
      containment = shared.size.to_f / [ tokens.size, candidate_tokens.size ].min
      [ jaccard, containment ].max
    end

    # Two stemmed tokens count as the same word when equal or when one is a
    # long prefix of the other (same length family): "restaurante" and
    # "restaurant". Short tokens are excluded so filler/irrelevant words never
    # trigger a fold.
    def token_close?(a, b)
      return true if a == b

      [ a, b ].sort_by(&:length).then do |shorter, longer|
        shorter.length >= 4 && longer.start_with?(shorter) && (longer.length - shorter.length) <= 3
      end
    end

    # Tokens collapsed to a singular-ish stem ("restaurantes" -> "restaurant",
    # "compras" -> "compra") so near-identical labels fold. This is spelling
    # normalization, NOT an unconditional classification rule.
    def fold_tokens(text)
      normalize(text).to_s.split.filter_map do |token|
        stem = token
        stem = stem[0...-2] if stem.length > 2 && stem.end_with?("es")
        stem = stem[0...-1] if stem.length > 1 && stem.end_with?("s")
        stem.present? ? stem : token
      end
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
  end
end
