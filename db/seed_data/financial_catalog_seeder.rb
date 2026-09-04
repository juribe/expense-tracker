# frozen_string_literal: true

# Idempotent seeder for the financial email catalog: Colombian institutions,
# global financial keywords and subject patterns.
#
#   FinancialCatalogSeeder.run
#
# Upserts by stable natural keys (canonical_name / value), so running it
# multiple times never creates duplicates. Values removed from the YAML files
# are left in place (they are harmless historical data) — the catalog is
# additive by design.
class FinancialCatalogSeeder
  DATA_DIR = Rails.root.join("db/seed_data")

  def self.run
    new.run
  end

  def run
    seed_institutions
    seed_keywords
    seed_subject_patterns
  end

  private

  def seed_institutions
    yaml("financial_institutions.yml").fetch("institutions", []).each do |attrs|
      institution = FinancialInstitution.find_or_create_by!(canonical_name: attrs["canonical_name"])
      institution.update!(
        aliases: Array(attrs["aliases"]),
        domains: Array(attrs["domains"]),
        keywords: Array(attrs["keywords"]),
        active: attrs.fetch("active", true)
      )
    end
  end

  def seed_keywords
    yaml("financial_keywords.yml").fetch("keywords", {}).each do |category, group|
      weight = group.fetch("weight", 1)
      group.fetch("values", []).each do |value|
        keyword = FinancialKeyword.find_or_create_by!(value: value) do |keyword|
          keyword.category = category
          keyword.weight = weight
        end
        keyword.update!(category: category, weight: weight) unless keyword.category == category && keyword.weight == weight
      end
    end
  end

  def seed_subject_patterns
    yaml("financial_subject_patterns.yml").fetch("subject_patterns", []).each do |value|
      FinancialSubjectPattern.find_or_create_by!(value: value)
    end
  end

  def yaml(filename)
    YAML.load_file(DATA_DIR.join(filename), aliases: true)
  end
end
