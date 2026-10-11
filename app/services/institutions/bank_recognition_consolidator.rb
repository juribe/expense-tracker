# frozen_string_literal: true

module Institutions
  # BankRecognitionConsolidator
  # One-time controlled consolidation of bank-level recognition values
  # (sender / domain / subject / header) after the bank-group redesign:
  #
  #   DRY_RUN=1 bin/rails institutions:consolidate_bank_recognition   # preview
  #   bin/rails institutions:consolidate_bank_recognition
  #
  # Per USER per bank group (attached entity, or folded legacy bank token):
  #   1. The SEED is the group's earliest source (min id) — the group's
  #      bank-level configuration source.
  #   2. CONFIRMED bank-level values found on non-seed members are MOVED to
  #      the seed (union, exact matches skipped — no duplicates) and REMOVED
  #      from the members, so the matcher never double-counts a bank and the
  #      siblings share one configuration through the seed.
  #   3. Product keywords (and last-four values) NEVER move: they identify
  #      individual cards/accounts.
  #   4. Suggested (unreviewed) rows are left untouched — the user still has
  #      to review them on the recognition page.
  #   5. A member record that ends up with zero identifiers is destroyed
  #      (same semantics as the recognition page editor).
  #   6. Re-runs are idempotent. Raw data is never lost: bank values RE-appear
  #      on the seed (origin "user").
  #
  # NOT a seed: it migrates user-owned data and must be run deliberately.
  class BankRecognitionConsolidator
    Outcome = Struct.new(:user_id, :group_key, :institution_label, :seed_id,
                         :moved, :moved_kinds, keyword_init: true)

    def self.run(dry_run: false)
      new(dry_run:).run
    end

    def initialize(dry_run: false)
      @dry_run = dry_run
      @outcomes = []
    end

    def run
      MoneySource.payment_sources.select(:user_id).distinct.pluck(:user_id).each do |user_id|
        consolidate_user(user_id)
      end
      summary
    end

    private

    def consolidate_user(user_id)
      MoneySource.where(user_id: user_id)
                 .payment_sources
                 .includes(recognition: :recognition_identifiers)
                 .order(:id)
                 .group_by { |source| group_key(source) }
                 .each { |key, members| consolidate_group(user_id, key, members) }
    end

    def group_key(source)
      if source.institution?
        "#{source.institution_type}:#{source.institution_id}"
      else
        token = SourceRecognition::TextNormalizer.fold(source.institution_token.to_s)
        token.blank? ? "source:#{source.id}" : "legacy:#{token}"
      end
    end

    def consolidate_group(user_id, key, members)
      seed = members.first
      moved = 0
      moved_kinds = Hash.new(0)

      members.each do |source|
        next if source.id == seed.id || source.recognition.nil?

        moving = confirmed_bank_identifiers(source)
        next if moving.empty?

        unless @dry_run
          ActiveRecord::Base.transaction do
            target = source.recognition
            recognition = seed.ensure_recognition
            recognition.save! if recognition.new_record?

            moving.each do |identifier|
              existing = recognition.recognition_identifiers.find_by(kind: identifier.kind, value: identifier.value)
              unless existing&.confirmed?
                recognition.recognition_identifiers.create!(
                  kind: identifier.kind, value: identifier.value,
                  status: "confirmed", origin: "user", position: next_position(recognition, identifier.kind)
                )
                existing&.destroy!
              end
              identifier.destroy!
            end

            # Nothing left at all → drop the (now empty) member record.
            source.recognition.reload
            source.recognition.destroy if source.recognition.recognition_identifiers.empty?
          end
        end

        moving.each { |identifier| moved_kinds[identifier.kind] += 1 }
        moved += moving.size
      end

      return if moved.zero?

      @outcomes << Outcome.new(user_id:, group_key: key, institution_label: seed.institution_name,
                               seed_id: seed.id, moved:, moved_kinds:)
    end

    def confirmed_bank_identifiers(source)
      source.recognition.recognition_identifiers
            .confirmed
            .select { |identifier| identifier.kind.in?(%w[sender domain subject header]) }
    end

    def next_position(recognition, kind)
      recognition.recognition_identifiers.where(kind: kind).maximum(:position).to_i + 1
    end

    def summary
      puts
      puts "Bank recognition consolidation#{' (DRY RUN - nothing written)' if @dry_run}"
      puts "  groups touched: #{@outcomes.size}"
      puts "  moved bank-level identifiers: #{@outcomes.sum { |outcome| outcome.moved }}"
      puts
      @outcomes.each do |outcome|
        puts format("  user=%-6s seed=%-7s label=%-24.24s moved=%s",
                    outcome.user_id, outcome.seed_id, outcome.institution_label.to_s,
                    outcome.moved_kinds.map { |kind, count| "#{kind}:#{count}" }.join(","))
      end
    end
  end
end
