# frozen_string_literal: true

# FinancialInstitution
# Seed-backed global catalog of Colombian financial institutions used by the
# cheap first-stage email filter and by the money-source institution selector
# (shared by all users — they may READ it, never modify it). Seeded
# idempotently from db/seed_data (see FinancialCatalogSeeder).
#
# Fields: canonical_name (commercial name), slug (stable identifier, unique),
# institution_type (bank / digital_bank / digital_wallet / financing_company /
# other), aliases and domains (candidate matching signals, NOT proof that an
# email is a transaction notification), active (inactive entities keep their
# historical money-source associations but no longer appear as options for
# new sources).
#
# Ownership managed by the seeds: slug, canonical_name and institution_type
# are admin attributes (set on creation); aliases/domains/keywords are seed
# candidate-signal attributes (upserted each run). `active` is deliberately
# NOT re-applied on update so manually disabled entities are never silently
# re-activated by seeds.
class FinancialInstitution < ApplicationRecord
  TYPES = %w[bank digital_bank digital_wallet financing_company other].freeze

  validates :canonical_name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/, message: :invalid }
  validates :institution_type, inclusion: { in: TYPES }, allow_blank: true

  before_validation :normalize_slug

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:canonical_name) }

  # Rename cascade: money sources cache the institution label when written;
  # if the catalog spelling is corrected later, the denormalized labels must
  # follow (cheap `update_all` — renames are rare and no user data moves).
  after_update :sync_money_sources_cached_name,
               if: -> { saved_change_to_canonical_name? }

  # Stable identifier for tests and lookups: by slug first, falling back to
  # canonical_name (pre-slug rows that the migration has not backfilled yet).
  def self.by_slug(slug)
    find_by(slug: slug)
  end

  def custom? = false

  def display_name = canonical_name

  # Folded (lowercase, accent-stripped) alias list used for text matching.
  def folded_aliases
    aliases.map { |a| SourceRecognition::Catalog.fold(a) }.reject(&:blank?)
  end

  def folded_domains
    domains.map { |d| SourceRecognition::Catalog.fold(d) }.reject(&:blank?)
  end

  private

  def sync_money_sources_cached_name
    MoneySource.where(institution_type: "FinancialInstitution", institution_id: id)
               .update_all(institution_cached_name: canonical_name)
  end

  def normalize_slug
    self.slug = slug.to_s.parameterize.presence
  end
end
