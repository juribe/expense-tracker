# frozen_string_literal: true

# SolidQueue supervisors/workers are long-lived processes: they never serve
# requests, so code reloading inside them is worthless and actively harmful.
# When code changes while `bin/dev` is up, the dev reloader redefines reload-
# eligible classes (SolidQueue::Process included) and the background threads
# keep the OLD class reference — registration then dies with
# "SolidQueue::Process(...) expected, got ..." (AssociationTypeMismatch).
#
# Procfile.dev starts the worker with RELOAD_OFF=1: this initializer turns
# reloading off in that process so bg workers survive hot editing. The web
# server keeps reloading normally.
Rails.application.config.enable_reloading = false if ENV["RELOAD_OFF"].present?
