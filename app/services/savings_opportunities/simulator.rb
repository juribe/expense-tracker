# frozen_string_literal: true

module SavingsOpportunities
  # SavingsOpportunities::Simulator
  # Builds the savings scenario from the user's real category spending and
  # precomputes every allowed reduction step in Ruby. The browser only reads
  # those numbers; it never decides how much money a percentage represents.
  #
  # Methods: call, self.total
  #
  # Example: SavingsOpportunities::Simulator.total(rows:, reductions: { id => 10 })
  class Simulator
    PERCENTAGES = (0..100).step(5).to_a.freeze
    MAX_ROWS = 5
    DEFAULT_PERCENTAGE = 10

    def self.total(rows:, reductions:)
      by_id = rows.index_by { |row| row[:id].to_s }

      reductions.sum(0.to_d) do |id, percentage|
        row = by_id[id.to_s]
        next 0.to_d unless row

        clamped = percentage.to_s.to_d.clamp(0, 100)
        (row[:current].to_d * clamped / 100).round(2)
      end
    end

    attr_reader :window, :categories

    def initialize(window:, categories:)
      @window = window
      @categories = categories
    end

    def call
      rows = categories.sort_by { |row| -row[:current] }.first(MAX_ROWS).map do |row|
        percentage = snap(row[:suggested_percentage])
        {
          id: row[:id],
          name: row[:name],
          current: row[:current],
          default_percentage: percentage,
          steps: PERCENTAGES.index_with { |step| (row[:current] * step / 100).round }
        }
      end

      {
        rows: rows,
        percentages: PERCENTAGES,
        default_total: rows.sum(0.to_d) do |row|
          row[:steps][row[:default_percentage]]
        end
      }
    end

    private

    # The slider only offers the PERCENTAGES steps, so the category's
    # configured rate is rounded to the nearest one.
    def snap(percentage)
      value = percentage.to_d
      PERCENTAGES.min_by { |step| (step - value).abs }.to_i
    end
  end
end
