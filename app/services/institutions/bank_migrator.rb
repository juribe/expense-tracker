# frozen_string_literal: true

module Institutions
  # BankMigrator
  # Controlled migration of the legacy free-text `money_sources.bank` values
  # to the polymorphic institution association. Run via:
  #
  #   DRY_RUN=1 bin/rails institutions:migrate_banks   # preview only
  #   bin/rails institutions:migrate_banks             # safe, additive write
  #
  # Rules (never destructive):
  #   1. The original bank text is NEVER cleared or modified.
  #   2. A source gets associated only on an UNAMBIGUOUS match: the folded
  #      bank text equals the global catalog's canonical name or one of its
  #      aliases (or the owner's custom institution name). Accents and
  #      punctuation are normalized for comparison only.
  #   3. Ambiguous matches (one value equal to two institutions) are reported
  #      for manual review, never resolved by guesswork.
  #   4. No match: the value is left as-is for the user to resolve in the UI
  #      (pick a catalog entity or create their own custom one).
  #   5. Already-associated sources and pocket sources (whose bank text is
  #      not an institution) are reported, never auto-bound.
  #
  # NOT a seed: it migrates user-owned data and must be run deliberately.
  class BankMigrator
    MigrationOutcome = Struct.new(:source, :bank, :institution, :status,
                                  keyword_init: true)

    def self.run(dry_run: false)
      new(dry_run:).run
    end

    def initialize(dry_run: false)
      @dry_run = dry_run
      @outcomes = []
      @institutions = FinancialInstitution.order(:id)
                                          .each_with_object({}) do |institution, index|
        index[institution.id] = {
          institution:,
          terms: ([ institution.canonical_name ] + Array(institution.aliases))
                 .map { |term| normalize(term) }.uniq.reject(&:blank?)
        }
      end
    end

    def run
      MoneySource.where.not(bank: [ nil, "" ])
                 .where(institution_id: nil)
                 .where.not(kind: %w[cash pocket])
                 .find_each { |source| migrate(source) }

      summary
    end

    private

    # Cash sources do not have a bank behind them, and pockets are detached
    # from any real account: their bank text is usually free-form garbage.
    # They are kept out of the automatic binding but still reported.
    def migrate(source)
      bank = source.bank.to_s.strip
      return record(source, bank, nil, :skipped) if bank == source.bank && bank.empty?

      matches = matching_institutions(source, normalize(bank))

      if matches.one?
        attach(source, matches.first)
        record(source, bank, matches.first, :associated)
      elsif matches.many?
        record(source, bank, nil, :ambiguous)
      else
        record(source, bank, nil, :unmatched)
      end
    end

    def matching_institutions(source, folded)
      global = @institutions.values
                           .select { |entry| entry[:terms].include?(folded) }
                           .map { |entry| entry[:institution] }
      custom = CustomFinancialInstitution
               .where(user_id: source.user_id)
               .select { |institution| normalize(institution.name) == folded }

      (global + custom).compact.uniq
    end

    def attach(source, institution)
      return if @dry_run

      source.update!(institution_type: institution.class.name, institution_id: institution.id)
    end

    def record(source, bank, institution, status)
      @outcomes << MigrationOutcome.new(source:, bank:, institution:, status:)
    end

    # Folded comparison value: lowercase, accent-stripped, punctuation-free,
    # single-spaced. "  Davivienda  " ~ "davivienda", "Nequi!" ~ "nequi".
    def normalize(text)
      SourceRecognition::TextNormalizer
        .fold(text)
        .gsub(/[^\w\s]/, "")
        .split
        .join(" ")
    end

    def summary
      counts = @outcomes.each_with_object(Hash.new(0)) { |outcome, counts| counts[outcome.status] += 1 }
      puts
      puts "MoneySource institution migration#{' (DRY RUN - nothing written)' if @dry_run}"
      puts "  associated : #{counts.fetch(:associated, 0)}"
      puts "  ambiguous  : #{counts.fetch(:ambiguous, 0)} (needs review)"
      puts "  unmatched  : #{counts.fetch(:unmatched, 0)} (needs review)"
      puts "  skipped    : #{counts.fetch(:skipped, 0)}"
      print_details("Ambiguous values (one text equal to several institutions):",
                    @outcomes.select { |o| o.status == :ambiguous })
      print_details("Values without any catalog match (associate manually in the UI):",
                    @outcomes.select { |o| o.status == :unmatched })
      counts
    end

    def print_details(title, outcomes)
      return if outcomes.empty?

      puts
      puts title
      outcomes.each do |outcome|
        puts format("  source_id=%-7s bank=%-32.32s source=%s",
                    outcome.source.id, outcome.bank, outcome.source.name)
      end
      puts
    end
  end
end
