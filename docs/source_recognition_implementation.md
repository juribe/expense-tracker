# Source Recognition — Implementation Guide

> Handoff document. The static markup prototype is already implemented and
> reviewed. Your job is to replace the fake data with real models, wire the
> actions, add suggestions, and guard the Gmail connection.
>
> **Prototype (already done, do not redo):**
> - View: `app/views/money_sources/recognition.html.erb` (fake data at the top,
>   clearly marked `FAKE DATA (replace me)`)
> - Route: `get "money_sources/recognition"` → `money_sources#recognition`
>   (`money_sources_recognition_path`)
> - CSS: `app/assets/stylesheets/application.css` — block
>   `/* Source Recognition (prototype) */`
> - Locales: `money_sources.recognition.*` in `config/locales/es.yml` and
>   `config/locales/en.yml`
> - Smoke test: `money_sources_controller_test.rb` →
>   `"GET /money_sources/recognition renders the prototype with fake data"`
>
> All user-facing strings MUST use the existing `money_sources.recognition.*`
> locale keys. Add new keys to BOTH `es.yml` and `en.yml` (Spanish is primary).

---

## 0. Non-negotiable product decisions

1. Do NOT add this configuration to the Money Source creation wizard or the
   Money Source create/edit form. Recognition is configured **only** from
   `/money_sources/recognition`.
2. The main table shows ONLY: Fuente de dinero, Tipo, Estado, Acciones.
   Never expose keywords/senders/subjects in the table.
3. Deleting recognition configuration must NEVER delete the Money Source.
4. Gmail OAuth must not start unless at least one source is configured
   (see §6). Do not scan the mailbox to generate configuration.
5. Do not refactor unrelated code. Keep the existing design language
   (reuse `--loan-*` CSS tokens and the card patterns already in `application.css`).

## 1. Inspect before coding

- `app/models/money_source.rb` — kinds (`account`, `debit_card`, `credit_card`,
  `cash`, `wallet`, `loan`), `debt?`, existing `MoneySourceTag` usage.
- `app/models/concerns` / existing tag model: `MoneySourceTag` belongs_to
  `money_source`, string `value`. NOTE: recognition identifiers are NOT the
  normal tags — do not reuse `MoneySourceTag`.
- `app/controllers/money_sources_controller.rb` — `FILTERS`, `kind_index_path`.
- `app/controllers/gmail_connections_controller.rb` — where OAuth starts
  (`start_auth`) and where to add the guard (§6).
- `app/assets/stylesheets/application.css` — the prototype CSS block.
- The existing `MoneySource` has `name` and `bank` — these feed suggestions (§4).

## 2. Data model

Create a migration + models (keep it minimal, two tables):

```
MoneySourceRecognition
  belongs_to :money_source
  has_many :recognition_identifiers, class_name: "MoneySourceRecognitionIdentifier",
           dependent: :destroy
  accepts_nested_attributes_for :recognition_identifiers,
           allow_destroy: true

MoneySourceRecognitionIdentifier
  belongs_to :money_source_recognition
  # kind: integer or string, in: TYPES
  # value: string, presence + length validation
  TYPES = %w[keyword sender domain subject header].freeze
```

- Migration 1: `money_source_recognitions` with
  `money_source_id` (null: false, foreign key, unique index) +
  timestamps.
- Migration 2: `money_source_recognition_identifiers` with
  `money_source_recognition_id` (null: false, foreign key, index),
  `kind` (null: false), `value` (null: false) +
  unique index on `[:money_source_recognition_id, :kind, :value]`.
- Add `has_one :recognition, class_name: "MoneySourceRecognition",
  dependent: :destroy` and `has_many :recognition_identifiers,
  through: :recognition` to `MoneySource`.
- Auto-create the `MoneySourceRecognition` record lazily (first save) — do not
  backfill; absence of the record == "Sin configurar".
- Normalize values before validation: strip, downcase for
  keywords/domains/senders (domains and email local parts are case-insensitive;
  keep subject/header patterns as typed).
- A source is **configured** when it has ≥ 1 identifier of any kind. Add
  `MoneySource#recognition_configured?`.

## 3. Status + table (wire the prototype)

- Controller `recognition` action: replace the in-view fixture with
  `current_user.money_sources.order(:kind, :name)` (include
  `recognition: :recognition_identifiers` to avoid N+1).
- Row markup stays as-is; swap the fake hash fields for real records:
  - `configured` → `source.recognition_configured?`
  - Actions: Edit always; Delete (recognition config) only when configured.
- Keep `data-testid` attributes; update the smoke test to build real records.

## 4. Suggestions (computed, never persisted until accepted)

Add `app/services/source_recognition/suggestion_engine.rb` (plain Ruby service,
no DB writes). Inputs: the `MoneySource` being edited. Outputs:

```
{
  keywords: [ { value:, source: :name } ],          # institution-level only
  senders:  [ { value:, source: <source name> } ],
  subjects: [ { value:, source: <source name> } ]
}
```

Rules:

1. **From the source's own name** (first-time configuration):
   - Tokenize `name` and `bank`. Lowercase, strip accents.
   - Institution tokens (e.g. "davibank", "bancolombia") → `keywords`
     suggestions tagged `source: :name`.
   - Product tokens (e.g. "clásica", "oro", "vehículo") → also suggest, BUT
     mark them as product-specific so the UI can explain them (§8 below).
2. **From siblings of the same institution** (source has `bank`, and other
   sources share the same `bank`):
   - Collect senders/domains and subject/header patterns configured on those
     siblings → suggest verbatim, with
     `source: <sibling source name>` so the UI can render
     "Sugerido desde Davibank Clásica".
   - **Never copy product-specific keywords from siblings.** Only suggest
     keywords that equal the shared institution token (e.g. "davibank").
     The sibling's product tokens ("clásica", "tarjeta clásica") must NOT be
     suggested to "Davibank Oro". This is a hard requirement (prompt §8).
3. **Exclude** values already configured on the current source.
4. Deterministic and cheap: no AI, no network calls.
5. "Same institution" = same normalized `bank` string (downcase, strip). If
   `bank` is blank there are no sibling suggestions.

### Suggestion UI (extend the edit panel)

Add a block **above** the three sections, only when suggestions exist:

```
"Configuración sugerida"
"Ya tienes otra fuente de DAVIbank configurada. Puedes reutilizar sus
 remitentes y encabezados."

Remitentes sugeridos:    [chip: value] [chip: value]
Encabezados sugeridos:   [chip: value]
[Sugerido desde Davibank Clásica]   ← small muted text under each group
[+ Agregar sugerencias]
```

- Suggested chips are visually distinct from configured chips (e.g. dashed
  border, muted background) and are NOT part of the form payload until the
  user clicks **"Agregar sugerencias"** (or removes/ignores them).
- Clicking "Agregar sugerencias" appends the suggested values into the
  corresponding chip sections as normal (unsaved) form values.
- First-time suggestions (from the source's own name) render the same way but
  the caption reads "Sugerido desde el nombre de la fuente".

## 5. Edit panel behavior

- Clicking Edit expands the panel **inline below the row** (prototype shows it
  as a section below the table — acceptable first iteration; keep it on the
  same page). Use `GET money_sources_recognition_path(edit: source.id)` or a
  dedicated `edit` route on the same page; no separate pages.
- The panel is a form (`form_with model: [source, recognition || build]`) with
  nested `recognition_identifiers` fields. Simplest robust implementation:
  one hidden field list per section (JS-managed chips) submitted as
  `identifiers: { keyword: [...], sender: [...], subject: [...] }` to a
  dedicated update endpoint, e.g.
  `patch "money_sources/recognition/:money_source_id",
  as: :money_source_recognition`.
- Server-side: upsert identifiers for the three kinds; delete any missing
  values (full replace per kind). Then `touch` nothing else.
- If all three kinds end up empty → destroy the recognition record → status
  becomes "Sin configurar" (§11).
- Footer: Cancelar (close panel, discard) / Guardar cambios (submit).

## 6. Gmail connection guard

In `GmailConnectionsController#start_auth` (before redirecting to Google):

```ruby
unless current_user.money_sources.any?(&:recognition_configured?)
  redirect_to money_sources_recognition_path,
    alert: t("money_sources.recognition.gmail_blocked")
  return
end
```

Do not scan historical mail or require mailbox access for configuration.
Tests: attempt OAuth with zero configured sources → redirected to recognition
page with the alert; with ≥ 1 configured source → proceeds.

## 7. Delete action

`delete "money_sources/recognition/:money_source_id",
as: :money_source_recognition_destroy` → destroys the recognition record
(destroying its identifiers). MoneySource must survive. Confirmation dialog
uses `money_sources.recognition.delete_confirm_title` and mentions
`delete_confirm_body` ("La fuente de dinero no será eliminada.").

## 8. Multiple sources / same institution

Nothing special in storage — each source has its own recognition record.
Institution-level identifiers ("davibank") will match several sources by
design; future matching must support multiple candidates. Do not add
uniqueness constraints across sources.

## 9. Tests (Minitest, follow existing patterns in
`test/controllers/money_sources_controller_test.rb`)

Model:
- `recognition_configured?` false without record / with empty record; true with ≥1 identifier.
- Value normalization (strip/downcase) and duplicate rejection per kind.
- Destroying recognition keeps the MoneySource.

Suggestion engine:
- First-time: name "Davibank Clásica" + bank "DAVIbank" → suggests
  `davibank`, `clásica` (product ones marked product-specific).
- Sibling reuse: second "Davibank Oro" suggests siblings' senders
  (`notificaciones@davibank.com`, `alertas@davibank.com.co`) and subjects
  ("Transacción aprobada", "DAVIbank te notifica") with sibling provenance.
- Hard requirement: sibling product keywords ("clásica", "tarjeta clásica")
  are NOT suggested to "Davibank Oro"; only institution-level "davibank".
- Already-configured values are excluded from suggestions.
- Blank bank → no sibling suggestions.

Controller:
- Recognition page lists all sources with correct statuses.
- Edit shows panel with current values (or empty for unconfigured).
- Update adds/removes keywords, senders, domains, subjects (per-kind replace).
- Saving all-empty removes configuration → "Sin configurar".
- Delete recognition keeps source; status flips to "Sin configurar".
- Gmail guard redirect (blocked + allowed).

## 10. Acceptance checklist

- [ ] Wizard/create-form untouched by recognition concerns.
- [ ] Table has exactly 4 columns; no keywords visible in it.
- [ ] "✓ Configurada" / "⚠ Sin configurar" statuses correct.
- [ ] Suggestions appear for first-time and same-institution cases.
- [ ] Product keywords never copied between siblings.
- [ ] Suggestions are explicitly accepted; never silently persisted.
- [ ] Delete recognition ≠ delete source (with confirmation dialog).
- [ ] Gmail OAuth blocked until ≥1 source configured; alert message shown.
- [ ] All strings localized (es + en); no hardcoded Spanish in views.
- [ ] `bin/rails test` green; no N+1 on the recognition page.
