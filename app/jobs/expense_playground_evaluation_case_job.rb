# frozen_string_literal: true

# Processes one evaluation case through the existing Expense Playground
# pipeline in a background job (large datasets never run in an HTTP request).
#
# Idempotent: a case that reached a terminal passed/failed status is never
# overwritten, so re-enqueueing is safe. Cases that ended in "error" are
# retried automatically (up to MAX_ATTEMPTS); a finished run can also be
# re-run from the UI, which resets terminal cases to pending and re-enqueues
# them.
class ExpensePlaygroundEvaluationCaseJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 3

  # Defence in depth: some vendor clients raise (timeouts, malformed replies)
  # instead of returning an error result; retry the whole attempt then.
  retry_on Ai::Provider::Error, Ai::Tasks::Base::InvalidResponse,
           wait: 5.seconds, attempts: 2

  def perform(evaluation_case_id)
    evaluation_case = EvaluationCase.find_by(id: evaluation_case_id)
    return if evaluation_case.nil?

    run = nil
    evaluation_case.with_lock do
      case_status = evaluation_case.reload.status
      return if case_status.in?(%w[passed failed])

      run = evaluation_case.evaluation_run
      return if run.nil? || run.failed?

      terminal = ExpensePlayground::Evaluations::CaseProcessor.call(
        run: run,
        evaluation_case: evaluation_case
      )

      if terminal == :error && retry_case?(evaluation_case)
        evaluation_case.update!(status: "pending", attempts: evaluation_case.attempts + 1)
        self.class.perform_later(evaluation_case.id)
      end
    end

    run&.update_progress!
  end

  private

  def retry_case?(evaluation_case)
    evaluation_case.attempts + 1 < MAX_ATTEMPTS
  end
end
