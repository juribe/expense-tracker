# frozen_string_literal: true

module ExpensePlayground
  module Evaluations
    # Starts an evaluation run: validates the dataset, persists the run and one
    # case per (valid) row, then enqueues a background job PER CASE so 1,000+
    # rows never block an HTTP request.
    #
    #   Runner.start(user:, content:, filename:, provider:, model:)
    #   # => { run:, invalid?, errors:, replayed?: }
    #
    # The endpoint is idempotent: re-submitting the same dataset with the same
    # provider/model returns the existing run instead of re-processing it.
    class Runner
      PROMPT_VERSION = "expense-extraction-v1"

      def self.start(user:, content:, filename:, provider:, model:)
        new(user: user, content: content, filename: filename, provider: provider, model: model).start
      end

      attr_reader :run, :errors, :invalid, :replayed

      def initialize(user:, content:, filename:, provider:, model:)
        @user = user
        @provider = provider.to_s.strip
        @model = model.to_s.strip
        @dataset = Dataset.build(content: content, filename: filename)
        @errors = []
        @invalid = false
        @replayed = false
        @run = nil
      end

      def start
        guard_parameters!
        return self if invalid

        replay_existing_run
        return self if run.present?

        create_run
        return self if invalid

        enqueue_cases
        self
      end

      def run_id
        run&.id
      end

      def result_payload
        {
          run_id: run_id,
          invalid: invalid,
          replayed: replayed,
          errors: errors
        }
      end

      private

      def guard_parameters!
        if @provider.blank? || @model.blank?
          @invalid = true
          @errors << "Both provider and model are required to run an evaluation."
        end
      end

      # Re-submitting the exact same dataset+params reuses the original run so
      # evaluations are idempotent and double-chargeable runs do not happen.
      def replay_existing_run
        return if invalid

        @run = EvaluationRun.find_by(
          user: @user,
          dataset_version: @dataset.checksum,
          provider: @provider,
          model: @model,
          prompt_version: PROMPT_VERSION
        )
        @replayed = true if @run
      rescue ActiveRecord::StatementInvalid
        @run = nil
      end

      def create_run
        return if invalid

        unless @dataset.valid?
          @invalid = true
          @errors = @dataset.errors
          return
        end

        @run = ActiveRecord::Base.transaction do
          record = EvaluationRun.create!(
            user: @user,
            dataset_name: @dataset.name,
            dataset_version: @dataset.checksum,
            provider: @provider,
            model: @model,
            prompt_version: PROMPT_VERSION,
            total_cases: @dataset.rows.length,
            status: "running",
            started_at: Time.current
          )
          @dataset.each_row do |row|
            EvaluationCase.create!(
              evaluation_run_id: record.id,
              row_number: row.number,
              message: row.message,
              expected_json: row.expected_json,
              status: "pending"
            )
          end
          record
        end
      end

      def enqueue_cases
        run.evaluation_cases.find_each do |case_record|
          ExpensePlaygroundEvaluationCaseJob.perform_later(case_record.id)
        end
      end
    end
  end
end