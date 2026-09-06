# Alertas de gasto — UI/UX Design Specification

*(Bootstrap 5.3 + Bootstrap Icons 1.10, ERB views, Plus Jakarta Sans, app design
tokens from `application.css` — `#5D87FF` primary, `#13DEB9` success, `#FFAE1F`
warning, `#FA896B` danger; sidebar navigation from `shared/_sidebar`. App
`I18n.default_locale = :es`, so labels below render through `t()` with Spanish
defaults (e.g. "Restaurantes"); mockup
`mockups/alertas_de_gasto.html` uses the repo's English mockup copy and
`$800,000` mockup money style — the real app renders `number_to_currency` →
`$800.000`.)*

## 0. Findings from the current app (decisions made from architecture)

- **Budgets do NOT exist yet.** There is no `Budget` model/table/controller.
  A spec already exists (`designs/presupuesto_por_categor_a.md`, "Nuevo
  model" `Budget(category_id, monthly_amount, period="monthly", active)`).
  → **Dependency:** alerts 1 & 2 (budget threshold/exceeded) consume
  `current_user.budgets` when present and are **inert when no budget exists**
  for a category. The alert engine must never require a budget.
- **No notification/toast/inbox infrastructure exists.** → Build a lightweight
  notification center (this spec) rather than integrating a new framework.
- **No user preferences model exists.** → One small
  `AlertPreference` table (3 booleans), not a generic prefs engine.
- **Transactions:** `Transaction` normalizes `kind` (`income`→positive,
  `expense`→negative signed `amount`); `Expense < Transaction` has
  `default_scope { expense }`, `in_month(date)`, `in_category(id)` scopes.
  `Transfer` is a **separate table**, never a `Transaction` → transfers are
  automatically excluded from spending.
- **Spend definition (single source of truth, shared with budgets):**
  `Expense.for_user(user).in_month(month).in_category(cat.id).sum(:amount).abs`
  → extract into a small service `CategorySpend.call(user:, category:, month:)`
  reused by **both** the budget cards and the alert engine, so refunds/income
  follow identical semantics everywhere. Refunds: follow existing business
  rules — whatever flow the app uses for refunds, the alert engine must NOT
  re-implement it; it only reads the same `CategorySpend` value budgets use.
- **Money/date formats:** `number_to_currency` (es → `$800.000`),
  `l(month, format: :month_year)` → "septiembre de 2026".

## 1. Goal and scope

Spending alerts with a personal-assistant tone ("You've used 82% of your
budget"), three alert types in v1, three settings, one lightweight center, and
a **guaranteed deduplication strategy** so alerts never re-fire on every
transaction.

Inline scope (minimal):
- Budget threshold (80%) alert — **active once a `Budget` exists**
- Budget exceeded (100%) alert — **active once a `Budget` exists**
- Unusual spending increase (≥ 35% vs previous month)

Settings: exactly the 3 toggles described in the task. Nothing more.

## 2. Data model (implementation-ready)

### 2.1 `spending_alerts` table

| column | type | notes |
|---|---|---|
| `user_id` | bigint, null: false, FK | |
| `category_id` | bigint, null: false, FK | every alert is category-scoped |
| `kind` | string, null: false | `budget_threshold` \| `budget_exceeded` \| `spending_increase` |
| `month` | string, null: false | `"YYYY-MM"` period the alert refers to |
| `pct` | integer, null: false | crossing % (82, 120) or increase % (38) |
| `amount` | decimal, null: false | spent (threshold/exceeded) or current-month spent (increase) |
| `previous_amount` | decimal, null: true | used only by `spending_increase` |
| `read_at` | datetime, null: true | null = unread |
| timestamps | | |

**Indexes:**
- `UNIQUE INDEX (user_id, kind, category_id, month)` → this is the
  deduplication guarantee (see §4).
- `INDEX (user_id, read_at)` for the unread-count query.

### 2.2 `alert_preferences` table (has_one on User)

| column | type | default |
|---|---|---|
| `user_id` | bigint, null: false, FK, unique | |
| `budget_threshold_enabled` | boolean, null: false | `true` |
| `budget_exceeded_enabled` | boolean, null: false | `true` |
| `spending_increase_enabled` | boolean, null: false | `false` |

Model convenience accessor `User#alert_prefs` returning a persisted row
(auto-build + save with defaults on first access). A missing row
(= a new user) means "use the defaults"; the engine must not crash.

### 2.3 Constants (single definition, in the service/model)

- `BUDGET_THRESHOLD_PCT = 80`
- `BUDGET_EXCEEDED_PCT = 100`
- `SPENDING_INCREASE_PCT = 35` (this can become a preference later; NOT in v1
  — the task says do not create dozens of settings)

## 3. Alert content and tone

Alerts are informative, not alarming. Three severities with a small icon chip,
a one-line message, a date, and an unread indicator. **No alert is ever
rendered red-on-white as a warning card.** Color is limited to the icon chip
and read badge.

| kind | icon | chip style | message template (t()/es) |
|---|---|---|---|
| `budget_threshold` | `bi-exclamation-triangle` | `bg-warning bg-opacity-10 text-warning` | "Restaurantes usó el 82% de su presupuesto mensual de $800.000." |
| `budget_exceeded` | `bi-exclamation-circle` | `bg-danger bg-opacity-10 text-danger` | "Compras excedió su presupuesto mensual por $120.000." |
| `spending_increase` | `bi-graph-up-arrow` | `bg-primary bg-opacity-10 text-primary` | "Tu gasto en Transporte es 38% mayor que el mes pasado ($500.000 frente a $362.000)." |

Messages are composed in a helper (`AlertsHelper#alert_message(alert)`), never
interpolated inline in views, reusing `number_to_currency`. Every alert row
links to the expenses list filtered to that category+month
(`expenses_path(category_id:, start_date:, end_date:)`).

## 4. Alert engine, transaction processing and dedup

### 4.1 Service

`SpendingAlertService.call(user:, category:, month:)`:
1. **Guards** — return early when the month is **not the current month**
   (v1 evaluates only the month of `Time.zone.today`; historic imports never
   flood the center) and when the corresponding preference is disabled.
2. Read `spent = CategorySpend.call(user:, category:, month:)`.
3. Budget alerts — only if a `Budget` exists for `(user, category)`:
   - `pct = spent / budget.monthly_amount * 100` (round for display).
   - If `pct >= 100` → candidate `budget_exceeded` (pct shown true, e.g. 120).
   - Else if `pct >= 80` → candidate `budget_threshold`.
4. Spending-increase alert — only if `spending_increase_enabled`:
   - `previous = CategorySpend(user:, category:, month.prev_month)`.
   - If `previous > 0` and `spent >= previous * (1 + SPENDING_INCREASE_PCT/100)`
     → candidate `spending_increase` (pct = rounded increase %).
5. **Dedup / persist** — for each candidate, `find_or_create_by!(user_id,
   category_id, kind, month)` with the computed facts. `create!` conflicts are
   rescued via the unique index (`RecordNotUnique` → already created, skip).
   **Alerts are insert-only and never updated**, so re-processing a month never
   changes an existing alert and never duplicates it.

### 4.2 Triggers (model-level, covers every write path)

`Transaction#after_commit on: [:create, :update, :destroy]`, only when the
record is an **expense** (kind == "expense"). Evaluate:
- **create / update:** the transaction's `month`.
- **update / destroy:** also the **previous** month of the transaction when
  `date` was changed (or the old date before destroy) so removing/editing a
  transaction can *remove the alert through the normal recompute below*.

Because this hook is model-level it automatically covers manual create
(`expenses#create`), AI bulk-create (`bulk_create`), Gmail sync (creates
`Expense` records), the setup-wizard import, and recurring "process_transaction"
— no controller wiring needed.

**Alert suppression on edit/destroy:** v1 recomputes (`call`) after the change;
the dedup guard must also delete an existing alert when the condition no longer
holds (`pct < threshold`). Implement as "recompute; if a row exists but the
candidate is no longer valid, delete it." This keeps "transaction updates" and
"refunds" test cases honest.

### 4.3 Rules that cannot regress

- **Transfers:** never expenses — `Transfer` is its own table; `CategorySpend`
  only queries `Expense`, so transfers are excluded structurally.
- **Refunds:** follow existing business rules; the engine reads the same
  `CategorySpend` value budgets use, never re-implements refund logic.
- **Month boundaries:** `in_month`/`CategorySpend` use
  `beginning_of_month..end_of_month` (inclusive); a transaction on the last
  day and one on the first day of adjacent months map to the correct month.
- **No spam:** one alert per `(kind, category, month)`; 80% fires once on the
  crossing transaction, not on every subsequent transaction.

## 5. UI — overview

Three surfaces, all using existing global chrome (sidebar + container):

1. **Alerts center** (`/alerts`, `AlertsController#index`) — the notification
   inbox: grouped list, read/unread, mark-all-as-read.
2. **Alert settings** (`GET/PATCH /settings/alerts`,
   `AlertSettingsController`) — 3 toggles, mirroring the `settings/gmail` route
   convention.
3. **Dashboard "Needs attention"** — compact card, non-dominating.

Navigation:
- **Sidebar** (`shared/_sidebar`), Overview section, right after Dashboard:
  ```erb
  <%= link_to alerts_path, class: "sidebar-link #{active_class('alerts')}" do %>
    <i class="bi bi-bell"></i><span><%= t("nav.alerts", default: "Alertas") %></span>
    <% if current_user.spending_alerts.unread.count.positive? %>
      <span class="badge bg-primary rounded-pill ms-auto"><%= current_user.spending_alerts.unread.count %></span>
    <% end %>
  <% end %>
  ```
- **Bell quick-access** — a `bi-bell` icon button with an unread-dot inside the
  right end of the `.mobile-topbar` (`ms-auto`), opening a small dropdown of the
  5 latest unread alerts + "View all". Desktop relies on the sidebar link; this
  keeps the layout free of floating overlap. (See `_alert_bell` partial §6.3.)

## 6. Components

### 6.1 Alerts center (`app/views/alerts/index.html.erb`)

**Header** (existing page-header pattern):
```erb
<div class="d-flex justify-content-between align-items-center mb-4 flex-wrap gap-2">
  <h1 class="mb-0"><i class="bi bi-bell me-2"></i><%= t("alerts.title", default: "Alertas") %></h1>
  <% if @unread_count.positive? %>
    <%= button_to mark_all_read_alerts_path, method: :patch, class: "btn btn-outline-primary" do %>
      <i class="bi bi-check2-all me-1"></i><%= t("alerts.mark_all_read", default: "Marcar leídas") %>
    <% end %>
  <% end %>
</div>
```

**Filter pills** (state kept in `params[:filter]`, default `all`):
`All (6)` · `Unread (2)` · `Budget` · `Spending`. Use
`nav nav-pills gap-2` with `nav-link` + `btn-sm`-style pills; the active pill
uses `bg-primary text-white`. Counts on Budget/Spending pills.

**Grouped list** — divide by month with a soft section header
(`text-muted small fw-semibold text-uppercase`, separators via
`border-bottom`):
- "Este mes" (`Time.zone.today` month) and then previous months, newest
  group first; within a group, `created_at` desc.
- Each alert row is a `card shadow-sm` with a `card-body p-3 d-flex
  align-items-start gap-3`, clickable → `PATCH /alerts/:id` marks read
  (Turbo) and reveals the linked expenses; unread rows have a
  `bi-circle-fill text-primary` dot and `bg-gray-100`-tint background
  (`style` var `--bs-gray-100`); when an alert is read the dot disappears.
- Row layout:
  - **Icon chip** — fixed `48px` square (`rounded-pill` is fine) with a
    `bi` icon + the severity tint from §3 (`accent` style, mirroring the
    loan/source `-soft` pattern: `background: rgba(color, .12)`).
  - **Content** — line 1: `fw-bold` category name + `badge` level label
    ("Cerca del límite" / "Sobre el presupuesto" / "Aumento de gasto");
    line 2: the helper-built message (§3); line 3 (`small text-muted`):
    relative date (`time_ago_in_words` + `l(date)`) and, for budget kinds,
    "Uso 82% de $800.000".
  - **Read/unread** — the dot in the icon row (never color-only) plus a
    visually-hidden "No leída" label (`visually-hidden`).
- **Empty state** (no alerts at all) — full-width card:
  `bi-bell-slash display-4 text-muted`, heading "Estás al día", text "Te
  avisaremos cuando un gasto se acerque a tu presupuesto o suba de forma
  inusual.", CTA `btn btn-outline-primary` "Configurar alertas"
  (`settings/alerts`). If filters produce zero rows, show a compact muted row
  "Sin alertas en este filtro."

**Loading/error:** Turbo default; error path → `alert alert-danger` +
  retry link (`bi-exclamation-circle`), mirroring the expenses `load_error`
  pattern. Success (mark-read) → Turbo flash `alert-success`.

### 6.2 Alert settings (`app/views/alert_settings/show.html.erb`)

Card form (`card shadow-sm`, `card-header bg-primary text-white` "Configuración de alertas" + `bi-bell`, `card-body`), reusing the categories-form footer pattern (Save `btn btn-primary` + `bi-check-lg`, Cancel `btn btn-outline-secondary`).

Three toggle rows in **two groups** (matching the task sketch exactly):
```
Presupuesto                 (group label, small text-muted fw-semibold uppercase)
  [switch on] Notificarme al usar el 80% de mi presupuesto        (budget_threshold_enabled)
  [switch on] Notificarme cuando supere mi presupuesto             (budget_exceeded_enabled)

Cambios en el gasto
  [switch off] Notificarme cuando el gasto sea notablemente mayor que el mes pasado   (spending_increase_enabled)
```
Each row: `form-check form-switch form-check-inline` + a one-line helper
(`small text-muted`). Use Rails labelable `check_box` with `class: "form-check-input"`; wrap rows in a `list-group list-group-flush` style container with `py-3 border-bottom` separators.

Footnote (noise control): `small text-muted` → "Recibirás cada alerta solo una
vez por mes y por categoría." — sets the dedup expectation for users.

Success: flash `alert-success` "Preferencias guardadas." Failure:
validation `alert-danger`.

### 6.3 Bell quick-access (`app/views/shared/_alert_bell.html.erb`)

Rendered in the layout on the right of `.mobile-topbar`
(`<div class="ms-auto">`). Bootstrap dropdown:
```erb
<div class="dropdown ms-auto d-flex align-items-center">
  <button class="btn btn-sm btn-link position-relative" type="button"
          data-bs-toggle="dropdown" aria-expanded="false" aria-label="Alertas">
    <i class="bi bi-bell fs-5"></i>
    <% if @unread_count.positive? %><span class="position-absolute translate-middle badge rounded-pill bg-danger">3</span><% end %>
  </button>
  <div class="dropdown-menu dropdown-menu-end p-0 shadow" style="width: 24rem;">
    <div class="d-flex justify-content-between align-items-center px-3 py-2 border-bottom">
      <span class="fw-bold"><i class="bi bi-bell me-1"></i>Alertas</span>
      <%= link_to alerts_path, class: "small" do %><%= t("alerts.view_all") %><% end %>
    </div>
    <div class="py-1">
      <% @recent_alerts.each do |alert| %> ... [row: icon dot + category + message] <% end %>
    </div>
    <div class="border-top px-3 py-2 text-center">
      <%= link_to alerts_path, class: "btn btn-sm btn-outline-primary w-100" do %>
        <i class="bi bi-bell me-1"></i><%= t("alerts.view_all") %>
      <% end %>
    </div>
  </div>
</div>
```
The count comes from a lightweight `before_action`/helper cached on the current
user (`current_user.spending_alerts.unread.count`). On mobile, the unread count
shows in the bell; on desktop the count lives in the sidebar badge. Both use
the same `spending_alerts.unread` scope.

### 6.4 Dashboard "Needs attention" (`app/views/dashboard/_needs_attention.html.erb`)

Placed **inside the existing `col-12 col-lg-4` right column, above the
quick-add form** (never in the top summary row) and **hidden entirely when
there are no alerts** so it never dominates:

```erb
<div class="card shadow-sm mb-0 mb-lg-3">
  <div class="card-header d-flex justify-content-between align-items-center bg-white">
    <h5 class="mb-0"><i class="bi bi-exclamation-circle me-2 text-warning"></i><%= t("dashboard.needs_attention", default: "Requiere atención") %></h5>
    <%= link_to alerts_path, class: "btn btn-sm btn-outline-primary" do %>
      <%= t("dashboard.view_all") %> <i class="bi bi-arrow-right ms-1"></i>
    <% end %>
  </div>
  <div class="card-body py-2">
    <% @attention_alerts.first(4).each do |alert| %>
      <%= link_to expenses_path(category_id: alert.category_id, start_date: "#{alert.month}-01"), class: "d-flex align-items-center gap-2 py-2 text-decoration-none text-body" do %>
        <i class="bi <%= alert_icon(alert) %> <%= alert_chip_text_class(alert) %>"></i>
        <span class="flex-grow-1 text-truncate"><%= alert.category.name %>: <%= t("alerts.pct_of_budget", pct: alert.pct) %></span>
      <% end %>
    <% end %>
  </div>
</div>
```
Keep rows to a single line each (`text-truncate`); only the *strongest*
alerts surface here (exceeded first, then threshold, then increase), sorted by
severity. The dashboard controller gains `@attention_alerts =
current_user.spending_alerts.unread.for_current_month to_a` (empty → partial
renders nothing).

## 7. States summary

| State | Treatment |
|---|---|
| Empty (no alerts) | Full-width "Estás al día" card + Configure CTA |
| Filter yields nothing | Compact muted "Sin alertas en este filtro" |
| Loading | Turbo defaults |
| Error (load) | `alert alert-danger` + retry |
| Success (mark read / prefs saved) | Flash `alert alert-success` |
| Unread alert | `--bs-gray-100` tint + `bi-circle-fill` dot + visually hidden "No leída" |
| Read alert | neutral, dot removed |
| Dashboard / bell with 0 alerts | component hidden |

## 8. Responsive behavior

- Alerts center list: single column full width (`col-12`); rows stack
  (icon on top, content below) below `sm` if needed, otherwise icon+content
  in-line. Month groups stay readable at all widths.
- Filter pills: `flex-wrap`; on mobile they wrap to 2 lines max.
- Settings toggles: rows stay full width on mobile; switch + label wrap
  cleanly (`form-check` handles it).
- Dashboard card: stacked column already collapses under the table on mobile;
  the needs-attention card sits above quick-add and stays compact.
- Bell dropdown: `width: 24rem` capped at `calc(100vw - 1rem)` on phones
  (`max-width: calc(100vw - 1rem)`).

## 9. Accessibility

- Every alert row is an interactive element (link/button) with a clear
  accessible name that includes category + level + message.
- Read/unread is never color-only: unread rows show a filled dot **and** a
  visually hidden "No leída" text; the sidebar/bell counts are text badges.
- Filter pills and mark-all buttons use `.visually-hidden` labels where the
  label is icon-only; severity chips include icon + text (never icon-only).
- Icon chips + colors respect the app tokens; `bg-warning` text uses
  `text-warning`/amber on white (not `text-white`) to keep contrast ≥ 4.5:1.
- Dropdown toggles have `aria-expanded` and `aria-label` ("Alertas");
  keyboard opens the panel via Bootstrap dropdown defaults.
- Reduced motion: no custom animations introduced (Turbo/Bootstrap defaults
  only).

## 10. Testing checklist (mapped from the task)

- **Threshold crossing** — spent exactly 80% fires; 79.9% does not.
- **80% alert** — one `budget_threshold` row created on the crossing
  transaction.
- **100% alert** — crossing 100% creates `budget_exceeded`; 99.9% does not.
- **Above-budget transactions** — later txns in the same month do not spawn a
  second alert (unique `(kind, category, month)`).
- **Duplicate prevention** — re-running the service / reprocessing the month
  yields no new rows; `RecordNotUnique` is swallowed.
- **Transaction updates** — editing an expense (amount/date/category) recomputes
  and deletes an alert that is no longer valid.
- **Refunds** — refunds recorded per existing business rules flow through
  `CategorySpend`; a refund that drops spend below 80%/100% removes the alert.
- **Transfers** — a transfer never raises an alert.
- **Month boundaries** — last day vs first day map to the right month; a
  past-month transaction produces no alert (v1 scope).
- **Read/unread** — mark-read endpoint toggles `read_at`; unread counts update.
- **Notification preferences** — disabled budget/spending toggles suppress
  their alert kinds; new users default correctly.

## 11. Routes reference

```ruby
resources :alerts, only: [ :index, :update ] do
  patch :mark_all_read, on: :collection
end
get "settings/alerts", to: "alert_settings#show", as: :alert_settings
patch "settings/alerts", to: "alert_settings#update"
```

## 12. Implementation order (recommended)

1. Migrations + models + unique index → 2. `CategorySpend` service + specs →
3. `SpendingAlertService` + dedup specs (all alert kinds, refunds, transfers,
   month boundaries) → 4. `after_commit` trigger → 5. Controllers/routes →
6. `_alert_bell` + sidebar badge → 7. Alerts center view → 8. Settings page →
9. Dashboard `_needs_attention` → 10. Playwright/UI pass. Budget-driven alert
kinds activate automatically once `Budget` (presupuesto spec) is implemented;
this spec never stubs or duplicates budget data.