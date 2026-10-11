# frozen_string_literal: true

# CustomFinancialInstitution
# A user-owned financial institution ("Otra entidad"): the entry a user
# creates when the shared FinancialInstitution catalog does not carry the
# entity they need. Private by design — only the owner lists, edits or
# deletes it, it is never exposed to other users, and it is never
# automatically promoted into the global catalog.
#
# A custom institution can back several of the owner's money sources, and it
# supports the same private UserInstitutionSetting recognition configuration
# as global entities (uniqueness user+institution is shared by both kinds).
class CustomFinancialInstitution < ApplicationRecord
  belongs_to :user
  has_many :money_sources, as: :institution, dependent: :restrict_with_error

  validates :name, presence: true,
                   uniqueness: { scope: :user_id, case_sensitive: false }
  validates :institution_type,
            inclusion: { in: FinancialInstitution::TYPES }, allow_blank: true

  before_validation :strip_name

  scope :ordered, -> { order(:name) }

  # Rename cascade: keep the denormalized labels on the owner's money sources
  # fresh when the user edits their custom entity (see MoneySource#institution_name).
  after_update :sync_money_sources_cached_name, if: -> { saved_change_to_name? }

  def custom? = true

  def display_name = name

  private

  def sync_money_sources_cached_name
    MoneySource.where(institution_type: "CustomFinancialInstitution", institution_id: id)
               .update_all(institution_cached_name: name)
  end

  def strip_name
    self.name = name.to_s.strip.presence
  end
end
