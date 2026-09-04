# frozen_string_literal: true

# FinancialInstitution
# Seed-backed catalog of Colombian financial institutions used by the cheap
# first-stage email filter. Seeded idempotently from db/seed_data (see
# FinancialCatalogSeeder). Aliases and domains are candidate matching
# signals, not proof that an email is a transaction notification.
class FinancialInstitution < ApplicationRecord
  validates :canonical_name, presence: true, uniqueness: true

  scope :active, -> { where(active: true) }

  # Folded (lowercase, accent-stripped) alias list used for text matching.
  def folded_aliases
    aliases.map { |a| SourceRecognition::Catalog.fold(a) }.reject(&:blank?)
  end

  def folded_domains
    domains.map { |d| SourceRecognition::Catalog.fold(d) }.reject(&:blank?)
  end
end
