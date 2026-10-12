# frozen_string_literal: true

# Controlled wipe of user-owned recognition state (per-source configs +
# suggestions, Gmail fetch criteria and setup suggestions). Keeps OAuth
# tokens, processed emails, money sources and the shared catalog intact.
# NOT part of db:seed: must be run deliberately.
namespace :recognition do
  desc "Reset ALL recognition configs/suggestions and Gmail email criteria " \
       "(search_config + setup_suggestions). OAuth and processed emails are kept. " \
       "DRY_RUN=1 previews without writing."
  task reset_all: :environment do
    SourceRecognition::Reset.run(dry_run: ENV.fetch("DRY_RUN", "0") == "1")
  end
end
