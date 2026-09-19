# frozen_string_literal: true

# Stores the exact messages sent to the provider and the raw model response
# content on every AI call, so the playground's AI routing panel can show the
# prompt/output for each request and latency analysis can see what produced
# it. Cache and deterministic resolutions record neither.
class AddPromptAndOutputToAiRequests < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_requests, :prompt, :jsonb
    add_column :ai_requests, :output, :text
  end
end
