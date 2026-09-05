# Design: Gmail Setup Sync (first-sync setup accelerator)

## Problem

The normal Gmail sync is built for **expense transactions** (compra / pago
emails). Its recognition discovery also runs on the wrong inputs, producing
**wrong data**:

1. Full subject lines containing amounts/merchants ("Compraste $50.000 en D1")
   are suggested as recurring subjects — they never repeat.
2. Gmail settings (`search_config`: senders / subject keywords) are never
   filled automatically; the user must type them manually.
3. There is no guided flow: the user is never asked "are these Gmail settings
   OK?" before being shown money-source suggestions.

## Goal

An explicit **Setup sync** that scans the mailbox for **bank transaction
emails** (broadly — statements, alerts, payment notices; NOT expense-merchant
emails), then walks the user through two confirmation steps:

1. **Step 1 — Gmail settings**: suggested senders / domains / subject keywords
   are prefilled; the user confirms (or edits) → saved into `search_config`.
2. **Step 2 — Money source suggestions**: the recognition page
   (`money_sources_recognition_path`) shows the suggestions the scan attached
   to the user's EXISTING money sources; the user confirms/dismisses (existing
   flow, which already feeds back via `ApplyToSearchConfig`).

## Non-goals

- No expense importing during setup sync (that stays the normal sync's job).
- No creation of new money sources from emails (suggestions attach to
  existing sources only, per product decision).
- Supersedes the old doc rule "do not scan the mailbox to generate
  configuration" (docs/source_recognition_implementation.md §0.4): the setup
  scan exists precisely for that, gated behind an explicit user action.

## Implementation

### 1. `Gmail::SetupScanService`

- Query: broad — `newer_than:180d -category:promotions -category:social`
  (no from/subject clauses), `MAX_MESSAGES = 150`.
- Per message: `FinancialEmailFilter` decides if it is a bank/financial
  notification (marketing rejected).
- For passed emails only:
  - `SourceRecognition::DiscoveryService` attaches money-source suggestions
    (existing behaviour, now fed by bank emails instead of expense emails).
  - Settings aggregation:
    - `senders`: full From address, counted.
    - `domains`: From domain, counted.
    - `subject_keywords`: the transactional catalog keywords actually found in
      the subject (high precision — no per-email noise), counted.
- Result persisted on `gmail_connections.setup_suggestions` (json):
  `{ scanned:, passed:, senders: [{value, count}], domains: [...],
     subject_keywords: [...] }`, top 8 per list, count desc.

### 2. Wrong-data fixes in `SourceRecognition::DiscoveryService`

- Subject suggestions become **templates**: the subject is cut at the first
  amount/card-number run ("Compraste por $50.000 en X" → "Compraste por"),
  digits-collapsed; a candidate needs ≥ 3 words to be suggested. Subjects
  without amounts keep the full cleaned line when ≤ 8 words.

### 3. Job + controller

- `GmailSetupSyncJob` mirrors `GmailSyncJob` (syncing state + summary),
  calls `SetupScanService`.
- `POST /gmail_connections/:id/setup_sync` → enqueue; the Gmail page polls
  via the existing `sync_status` endpoint.
- `GET /gmail_connections/:id/setup` → step-1 page: form prefilled from
  `setup_suggestions` (falls back to current config); on submit the existing
  `update` action saves `search_config` and redirects to the recognition page
  (step 2) when `next=recognition`.

### 4. UI

- Gmail page: "Setup sync" button next to "Sync now"; when
  `setup_suggestions` exist, a "review suggestions" card links to step 1.
- Step 1 page saves settings → notice → recognition page (step 2) already
  lists per-source suggested chips with confirm/dismiss.

### Tests

- `test/services/gmail/setup_scan_service_test.rb` — aggregation, filtering,
  discovery wiring, failure isolation.
- `test/services/source_recognition/discovery_service_test.rb` — subject
  template behaviour (amounts stripped, short/noisy subjects skipped).
- `test/controllers/gmail_connections_controller_test.rb` — setup actions.
