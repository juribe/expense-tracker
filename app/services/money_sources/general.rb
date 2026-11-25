# frozen_string_literal: true

module MoneySources
  # Guarantees the single General source every user needs.
  #
  # Simple accounts hold it as the basic `general` kind; advanced accounts hold
  # it as a regular savings account (the conversion keeps the same record).
  # Creation is idempotent and race-safe through the partial unique index.
  #
  #   MoneySources::General.ensure_for(user)
  class General
    NAME = "General"

    class << self
      def ensure_for(user)
        return if user.nil? || !user.persisted?

        existing = user.money_sources.find_by(general: true)
        return existing if existing

        # Reuse a non-debt source already named General (for example after a
        # migration rollback/re-run) instead of creating a duplicate record.
        named = user.money_sources.where(name: NAME, kind: %w[account cash wallet debit_card general])
                    .order(:created_at, :id).first
        return adopt(user, named) if named

        create_for(user)
      end

      # Switching back to simple reuses the latest archived General when no
      # active one exists. Other archived sources stay archived; only General
      # is restored because simple tracking depends on it.
      def ensure_for_simple(user)
        return if user.nil? || !user.persisted?

        active = user.money_sources.find_by(general: true)
        return active if active

        archived = MoneySource.with_deleted
                              .where(user_id: user.id, general: true)
                              .where.not(deleted_at: nil)
                              .order(deleted_at: :desc, created_at: :desc)
                              .first
        if archived
          archived.update!(deleted_at: nil, active: true)
          return archived
        end

        create_for(user, kind: "general")
      end

      def create_for(user, kind: nil)
        kind ||= user.money_tracking_simple? ? "general" : "account"
        source = user.money_sources.create!(name: NAME, kind: kind, general: true)
        source
      rescue ActiveRecord::RecordNotUnique
        user.money_sources.find_by!(general: true)
      rescue ActiveRecord::RecordInvalid
        user.money_sources.find_by(general: true) || raise
      end

      private

      def adopt(user, source)
        source.update!(general: true)
        source
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
        user.money_sources.find_by(general: true) || raise
      end
    end
  end
end
