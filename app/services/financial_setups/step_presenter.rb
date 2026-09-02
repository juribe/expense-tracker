# frozen_string_literal: true

module FinancialSetups
  # StepPresenter
  # Prepares the per-step "Added" summary for the wizard's step screen, so the
  # view stays logic-free. Combines the manual drafts (draft_sources) with the
  # confirmed import sources (import_state), deduplicates them, and derives the
  # display values (masked identifier, amount to show) per source kind.
  #
  # The import flow can hold a copy of an already-added account, so every count
  # and list on the step screen must come from the same deduplicated list.
  #
  # Example: StepPresenter.new(setup: setup, step: FinancialSetupWizard.step(:accounts))
  class StepPresenter
    # Stable identity for a stored row: digits-normalized identifier when
    # present, else bank and name. Shared by the view, the combined editor and
    # remove_source so indexes always agree.
    def self.dedup_key(row)
      identifier = row["identifier"].to_s.gsub(/\D/, "")
      identifier.presence || "#{row["bank"]}-#{row["name"]}"
    end

    def initialize(setup:, step:)
      @setup = setup
      @step = step
    end

    def step_key
      @step.key.to_s
    end

    # Cash lives in your pocket — there is no statement to import.
    def importable?
      @step.kind != "cash"
    end

    # Combined manual + import rows, deduplicated. Ties keep the manual row.
    def added_sources
      tagged_rows.uniq { |row| self.class.dedup_key(row) }
    end

    def added_count
      added_sources.size
    end

    def has_added?
      added_count.positive?
    end

    # Row shown at an index of the combined list (the remove_source contract).
    def added_at(index)
      added_sources[index]
    end

    # Rows for the combined editor: each tagged with the store it came from
    # ("origin") and the identity it was rendered with ("orig_key"), so saving
    # routes edits back and never loses fields that are not in the form.
    def edit_rows
      tagged_rows.uniq { |row| self.class.dedup_key(row) }.map do |row|
        row.merge("orig_key" => self.class.dedup_key(row))
      end
    end

    # Masked identifier for badges: card last four when set, else the last four
    # digits of the identifier.
    def masked_last_four(row)
      row["card_last_four"].presence || row["identifier"].to_s.gsub(/\D/, "")[-4, 4]
    end

    # The money figure the step list shows for a row.
    #   credit_card -> available credit (limit - debt) when a limit exists
    #   loan        -> outstanding balance ("balance" may hold extraction junk)
    #   others      -> current balance
    def display_amount(row)
      case @step.kind
      when "credit_card"
        available_credit(row)
      when "loan"
        row["outstanding_balance"].presence || row["balance"]
      else
        row["balance"].presence
      end
    end

    private

    def tagged_rows
      @setup.draft_sources(step_key).map { |row| row.merge("origin" => "manual") } +
        Array(@setup.import_state(step_key)["sources"]).map { |row| row.merge("origin" => "import") }
    end

    def available_credit(row)
      limit = row["credit_limit"].to_d
      return nil if limit <= 0

      [ limit - row["balance"].to_d, 0 ].max
    end
  end
end
