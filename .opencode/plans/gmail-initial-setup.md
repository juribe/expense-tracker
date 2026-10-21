# Plan: Improve Gmail initial setup discovery flow

## Goal
Make the Gmail import setup self-serve: a user connects Gmail, clicks "Buscar mis notificaciones bancarias", the app scans the mailbox, suggests senders/domains/subject keywords, lets the user review/edit/save them, then enables "Sincronizar ahora" and normal import.

## State model (GmailConnection)
Add/adjust predicates:
- `setup_completed?` — true when `setup_suggestions` is a non-empty hash (initial scan finished).
- `search_configured?` — true only when criteria are actually usable for normal sync: `last_synced_at` present OR `saved_search_config?` (manual/confirmed criteria saved). Do NOT treat a completed scan alone as configured.
- Keep aliases for `search_configured?`: `criteria_configured?`, `sync_ready?`, `ready_to_sync?`, `configured_for_sync?`, `has_search_criteria?`, `has_saved_criteria?`, `criteria_saved?`, `initial_sync_done?`, `configured?`.
- Keep `saved_search_config?` checking canonical keys.

## Backend changes
1. `GmailConnectionsController#setup_sync`
   - Keep enqueuing `GmailSetupSyncJob`.
   - Keep the existing redirect to `money_sources_recognition_path` because recognition/source suggestion handling already lives there; do not move that flow.
   - Claim `syncing` before redirect (existing).
   - When the user returns to the Gmail page, show suggested criteria from `setup_suggestions` merged into the existing form (`criteria_form_values`).
2. `Gmail::SyncService#call` and `GmailSyncJob#sync_one`
   - Already guard with `search_configured?`; keeps normal sync disabled until criteria saved.
3. Error/empty handling
   - Surface `last_sync_summary["error"]` in the view when present.
   - Show an empty-results hint when `setup_completed?` but suggestions are blank.

## View changes (`app/views/gmail_connections/index.html.erb`)
Unconfigured + not scanned + not syncing:
- Header: no sync buttons.
- Primary card title: "Deja que encontremos tus notificaciones bancarias".
- Body text: specified discovery explanation.
- Button: "Buscar mis notificaciones bancarias" -> `setup_sync`.
- Keep connection status card.

Syncing:
- Show loading state (spinner + "Analizando tus correos...") and disable button.
- Poll via existing `sync_status`.

Scanned but not configured:
- Show suggested criteria in existing form (already via `criteria_form_values`).
- Explain fields in plain language.
- "Guardar criterios" saves via existing `update`.
- Link to recognition page for money-source suggestions if desired.
- Do not show "Sincronizar ahora".

Configured:
- Header shows "Sincronizar ahora".
- Primary card becomes completed state ("Configuración completada" + periodic sync explanation).
- Criteria form stays editable.

## Locale changes
Add keys (es/en) for:
- `gmail.find_notifications` = "Buscar mis notificaciones bancarias"
- `gmail.discover_title`
- `gmail.discover_body`
- `gmail.discovering`
- `gmail.config_completed`
- `gmail.config_completed_help`
- `gmail.empty_discovery`
Maybe update `gmail.criteria_help` / `criteria_help_manual`.

## Tests to add/update
- Unconfigured state renders new title/body/button and no header sync buttons.
- Scanned state renders suggested criteria fields and save button, no sync button.
- Configured state renders sync button and completed message.
- Empty/error discovery states.
- Manual criteria preservation (scan suggestions merge, not overwrite).
- Existing sync/import/dedup tests remain green with configured connections.

## Notes
- Reuse existing `SetupScanService`, job, polling, and criteria form.
- Do not create a second import system.
- Do not mark configured on scan failure.
