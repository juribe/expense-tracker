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
#
# Attribute ownership (institution entries):
#   * Managed at CREATION only: slug, active. A manually disabled institution
#     is therefore never re-activated by a later seed run.
#   * Managed on every run: aliases, domains, keywords, institution_type —
#     the YAML is the single source of truth for catalog metadata.
#   * Never touched: any per-user data (the catalog is global; personal data
#     lives in CustomFinancialInstitution / UserInstitutionSetting).
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
      institution = FinancialInstitution.find_or_initialize_by(canonical_name: attrs["canonical_name"])
      institution.assign_attributes(
        aliases: Array(attrs["aliases"]),
        domains: Array(attrs["domains"]),
        keywords: Array(attrs["keywords"]),
        institution_type: attrs["institution_type"].presence
      )
      # Admin-owned attribute set at creation only: a stable slug is never
      # overwritten by later runs.
      institution.slug = attrs["slug"].to_s.parameterize if institution.slug.blank?
      # `active` is NEVER assigned here — the seeds may not re-activate an
      # institution that was disabled manually after its creation.
      institution.save!
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
