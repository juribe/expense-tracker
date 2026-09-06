# Presupuesto por categoría — UI/UX Design Specification

*(Bootstrap 5.3 + Bootstrap Icons 1.10, ERB views, Plus Jakarta Sans, app design
tokens from `application.css` (Modernize palette: `#5D87FF` primary, `#13DEB9`
success, `#FFAE1F` warning, `#FA896B` danger); `I18n.default_locale = :es`, so
every label below renders through `t()` with a Spanish default — the app shows
Spanish, e.g. "Restaurantes". Mockup `mockups/presupuesto_por_categor_a.html`
uses the repo's standard English mockup copy + `$800,000` money style; the real
app renders `number_to_currency` → `$800.000` (es locale).)*

## 1. Goal

Let users define a **monthly spending budget per category**, see at a glance how
much they have spent, how much remains, and their status (on track / near limit /
over budget). Progress is computed from actual expenses for the selected month
and category, reusing the existing `Expense` scope logic — no business rules
duplicated in views.

## 2. Where it fits

- **New nav section**: add a "Presupuestos" link in the sidebar **Informes**
  (reports) section, right after "Reportes", using `active_class('budgets')`:

  ```erb
  <%= link_to budgets_path, class: "sidebar-link #{active_class('budgets')}" do %>
    <i class="bi bi-bullseye"></i>
    <span><%= t("nav.budgets", default: "Presupuestos") %></span>
  <% end %>
  ```

- **Routes**: `resources :budgets` (index / new / create / edit / update /
  destroy). Index accepts `?month=YYYY-MM` (same convention as the dashboard's
  `params[:month]`) for navigating to previous months.
- **Controller**: `BudgetsController < ApplicationController` with
  `before_action :authenticate_user!`; index filters budgets to
  `current_user` and resolves `@month` (defaults to `Time.zone.today`).

## 3. Domain surface (UI relies on, never reimplements)

| Data / helper | Source of truth | Used by |
|---|---|---|
| `Budget(category_id, monthly_amount, period="monthly", active)` | New model, belongs_to `user` + `category` | Form + cards |
| `current_user.budgets` | Model assoc | Index |
| `Category.for_user_and_type(current_user, "expense")` | Existing model scope | Form category select (expense types only) |
| Spent for a category+month | `Expense.for_user(user).in_month(month).in_category(cat.id).sum(:amount).abs` (reuse `in_month` + `in_category` scopes; amount is stored negative for expenses) | Card computation |
| Transfers excluded | `Transfer` is a separate table, never a `Transaction` | Automatic — nothing to add |
| Income/refunds follow existing semantics | `kind` normalization (`income`→positive, `expense`→negative) | Automatic |
| `credit_utilization_class(pct)` thresholds (`>80` danger, `>=50` warning) | Existing ApplicationHelper precedent | Progress bar color logic pattern |

**Status thresholds** (single definition, reused by cards + dashboard summary):

- `pct > 100` → **over_budget** (`bg-danger`, `bi-x-circle`, "Superado")
- `pct >= 80` → **near_limit** (`bg-warning`, `bi-exclamation-triangle`, "Cerca del límite")
- otherwise  → **on_track** (`bg-success`, `bi-check-circle`, "En camino")

`pct = (spent / monthly_amount) * 100`, rounded to integer for display; the bar
width is capped at 100 but the label shows the true percentage (e.g. 124%).

Budget progress always targets **expense** categories; income categories are not
budgeted in v1.

## 4. Presupuestos index

### 4.1 Page header (reuse existing pattern)

```erb
<div class="d-flex justify-content-between align-items-center mb-4 flex-wrap gap-2">
  <h1><i class="bi bi-bullseye me-2"></i><%= t("budgets.title", default: "Presupuestos") %></h1>
  <%= link_to new_budget_path, class: "btn btn-primary" do %>
    <i class="bi bi-plus-lg me-1"></i><%= t("budgets.new", default: "Nuevo presupuesto") %>
  <% end %>
</div>
```

### 4.2 Month navigation (matches dashboard `?month=` UX)

A slim toolbar row below the header:

- `btn btn-outline-secondary btn-sm` with `bi-chevron-left` → `budgets_path(month: @month.prev_month)`
- Center: `h5 mb-0` with `l(@month, format: :month_year)` (→ "Septiembre 2026")
- `btn btn-outline-secondary btn-sm` with `bi-chevron-right` → `budgets_path(month: @month.next_month)`
- When the user navigates to a non-current month, show a muted helper
  `Presupuesto del mes actual` pill/badge (`badge bg-light text-dark`) when
  `@month` is the current month; otherwise a small link "Volver al mes actual".

### 4.3 Summary strip (optional, restrained)

Only when budgets exist; one line, `text-muted small`, using the status counts
from the current month: `"3 presupuestos · 1 cerca del límite · 0 superados"`.

### 4.4 Budget cards

Grid: `row g-3` with `col-12 col-md-6 col-lg-4`, card `card h-100 shadow-sm`
(`h-100` so all cards equal height). Card body layout:

- **Header row** — `d-flex justify-content-between align-items-start mb-2`:
  - `category_badge(category)` (existing helper) wrapped in an optional link to
    the category show page.
  - `btn-group btn-group-sm d-print-none`: edit `btn btn-outline-primary`
    `bi-pencil` (link to `edit_budget_path`) + delete `btn btn-outline-danger`
    `bi-trash` via `button_to budget_path(budget), method: :delete`,
    `data: { confirm: t("common.confirm") }`. If the budget is inactive, show a
    `badge bg-secondary` "Inactivo" next to the badge.
- **Metric block** — a row of three compact stats (`d-flex justify-content-between
  text-center` on mobile stacking to full width). Each stat is a
  `small text-muted` label + a `fw-bold` value:
  - **Presupuesto** — budget amount, `text-body-emphasis` style strong value.
  - **Gastado** — spent, `text-danger` (spending is always expense-styled).
  - **Disponible** (on track/near limit) — `budget - spent`, `text-success`.
    **Over budget** replaces this with **"Excedido $72.000"**, `text-danger`,
    labelled "Excedido" so the meaning survives without color.
- **Progress bar** — `progress` (height 8px) + `progress-bar`
  `<%= credit_utilization_class(pct) %>`-style class (bg-success/bg-warning/
  bg-danger), `role="progressbar"`, `aria-valuenow` = true pct,
  `aria-valuemin="0" aria-valuemax="100"`, width `[pct, 100].min%`. Footer row:
  `small text-muted fw-semibold` label "Uso" + `fw-bold` percentage
  (true %, e.g. `124%`).
- **Status line** — `badge` with icon + text (never color only):
  - on track: `<span class="badge bg-success"><i class="bi bi-check-circle me-1"></i>En camino</span>`
  - near limit: `<span class="badge bg-warning text-dark"><i class="bi bi-exclamation-triangle me-1"></i>Cerca del límite</span>`
  - over budget: `<span class="badge bg-danger"><i class="bi bi-x-circle me-1"></i>Superado</span>`

Money values render through `number_to_currency` (es locale → `$800.000`),
identical to the dashboard's expense table.

### 4.5 Empty state

No budgets at all → existing empty-state pattern:

```
card shadow-sm > .p-5.text-center
  bi-bullseye display-4 text-muted
  h4 "Aún no tienes presupuestos"
  p "Crea un presupuesto mensual por categoría para controlar tus gastos."
  btn btn-primary "Nuevo presupuesto"  (bi-plus-lg)
```

If budgets exist but none for the visible filter (not possible in v1: budgets
are global/recurring), leave the grid empty with the month nav still usable.

### 4.6 Loading / error

- Loading: Turbo default + optionally the same `.skel` skeleton used in
  `expenses/index` if pagination is later added (not needed in v1).
- Error: `alert alert-danger` with `bi-exclamation-circle` + a retry link,
  mirroring the expenses `load_error` pattern.

## 5. Create / Edit form

Reuse the `categories/_form` card structure exactly:

- `card shadow-sm border-0` with `card-header bg-primary text-white`
  ("Nuevo presupuesto" / "Editar presupuesto", `bi-bullseye`), `card-body`
  `row g-3`, `card-footer d-flex justify-content-end gap-2` with Cancel
  (`btn btn-outline-secondary`, back to `budgets_path`) + Save
  (`btn btn-primary`, `bi-check-lg me-1`).
- **Category** — `form.collection_select :category_id,
  Category.for_user_and_type(current_user, "expense"), :id, :name,
  { prompt: "Selecciona una categoría" }, class: "form-select #{field_class(budget, :category_id)}"`.
  Category field disabled on edit (budget is bound to its category); v1 keeps it
  fixed to avoid confusion.
- **Monto mensual** — `input-group` with `<span class="input-group-text">$</span>`
  and a `form.text_field :monthly_amount, value: money_field_value(budget.monthly_amount),
  inputmode: "decimal", autocomplete: "off", data: { money_input: true }`
  (matches the dashboard quick-add / expenses filters).
- **Periodo** — v1 fixed: a read-only field showing
  `badge bg-light text-dark` + `bi-calendar-month` "Mensual" (or disabled
  `form-select`). No forecasting, no annual budgets.
- Validation feedback: `field_class`/`field_error` helpers (red highlight +
  `invalid-feedback` with `bi-exclamation-circle`), same as categories form.
- Success: flash notice `alert alert-success` (layout default) + redirect to
  `budgets_path`.

## 6. Dashboard integration (small, non-disruptive)

Add a compact "Presupuestos" card stacked **below** the quick-add form inside the
existing `col-12 col-lg-4` (second row) — the top summary row stays untouched to
avoid overcrowding:

```
card shadow-sm h-100
  card-header d-flex justify-content-between align-items-center bg-white
    h5 "Presupuestos" (bi-bullseye me-2)
    link_to budgets_path, "Ver todos" (bi-arrow-right ms-1) — btn-sm btn-outline-primary
  card-body
    (top 4 budgets, current month only)
    row per budget: category_badge + tiny progress (height 6px) + "78%" fw-bold
    footer: small text-muted "3 presupuestos · 1 cerca del límite · 0 superados"
```

Hide the whole card (or show the empty CTA) when no budgets exist. Progress bars
reuse the same status colors as §4.4. Only show if there is data for the current
month — the dashboard must not grow vertically.

## 7. Responsive behavior

- Cards: `col-12` → `col-md-6` (2-up) → `col-lg-4` (3-up), matching expenses/categories grids.
- Metric stats inside a card: three `col-6`/`col-4` mini-columns via
  `d-flex flex-wrap` so two stats per row on very narrow screens; card never
  overflows (amounts use `font-variant-numeric: tabular-nums`).
- Header: `flex-wrap gap-2` so the primary button wraps under the title on mobile.
- Month nav toolbar: `flex-wrap`, buttons stay visible (`btn-sm`).
- Dashboard mini-card: bottom of the `col-lg-4` column already collapses under
  the table on mobile.

## 8. Accessibility

- Progress bars: `role="progressbar"` with `aria-label` ("Uso de presupuesto de
  Restaurantes"), `aria-valuenow/min/max`.
- Status never by color alone: icon + text label in the badge (§4.4).
- Icon buttons have `aria-label`/`title` (e.g. `t("budgets.edit_aria")`); delete
  uses `button_to` + confirm dialog.
- Month navigation buttons carry `aria-label` ("Mes anterior"/"Mes siguiente").
- Color contrast: `bg-warning` badges use `text-dark`; danger on white uses the
  app token `#FA896B` which already meets the existing warning thresholds used
  elsewhere; on-track success uses `text-success`.

## 9. States summary

| State | Treatment |
|---|---|
| Empty (no budgets) | Full-width empty card + CTA |
| Loading | Turbo defaults / skel skeleton |
| Error (load) | `alert alert-danger` + retry |
| Validation error (form) | `is-invalid` fields + `invalid-feedback`, error summary `alert alert-danger` |
| Success (create/update/delete) | Flash `alert alert-success` |
| On track | success badge/bar, "Disponible" `text-success` |
| Near limit (≥80%) | warning badge/bar, "Disponible" `text-warning`-tinted but still numeric |
| Over budget (>100%) | danger badge/bar, "Excedido" `text-danger`, bar capped at 100, pct shows true value |

## 10. Testing checklist (mapped from the task)

- Budget creation / editing / deletion (controller + model).
- Spending calculation for the month+category (sum of `ABS(amount)`, expense
  kinds only).
- Remaining amount = monthly_amount − spent; over budget shows excedido.
- Percentage = spent / monthly_amount.
- Over-budget state (pct > 100) and near-limit state (pct ≥ 80) thresholds.
- Transfers excluded (Transfer rows never in `Expense`).
- Correct month calculation (`in_month` boundaries: beginning..end of month).
- Run relevant specs (model/service/controller/request) — no unrelated refactors.