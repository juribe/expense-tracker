# frozen_string_literal: true

# Join between a clarification session and one of the incomplete candidates
# it groups. Candidates keep their own missing_fields/status; the snapshot
# records what was missing when the candidate entered the session.
class ExpenseClarificationCandidate < ApplicationRecord
  belongs_to :expense_clarification
  belongs_to :expense_candidate

  validates :expense_candidate_id, uniqueness: { scope: :expense_clarification_id }
end
