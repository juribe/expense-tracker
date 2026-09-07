# Reglas automáticas — UI/UX Design Spec

Automatic transaction rules that categorize and organize transactions with minimal
manual work. Users author simple "Cuando… / Entonces…" rules and the system applies
them on create/import/sync. Users always stay in control (manual override always
allowed, rule suggestions are never auto-created).

Follows the `expense-tracker` design system (Bootstrap 5.3, Bootstrap Icons,
ERB, ApplicationHelper). UI copy is English (per project convention); sample
data uses realistic Spanish merchant names.

---

## 1. Placement & navigation

- Route namespace: `resources :transaction_rules` (plural) under an
  `Automation` concept.
- Add a nav entry in `shared/_sidebar`: **"Rules"** with `bi-magic` icon,
  `active_class('transaction_rules')`.
- Also link from the Expenses index toolbar ("Auto-categorize" affordance) so
  users who are tired of re-categorizing discover it in context.

Routes:

```ruby
resources :transaction_rules do
  collection { post :toggle_active }  # per-record toggle via member instead
end
```

Prefer member `patch :toggle_active` on each rule.

---

## 2. Data model (for design reference, implemented by Developer)

Because no tags model exists today (tags were migrated to
`MoneySourceRecognitionIdentifier`), the first version introduces one
`TransactionRule` model owned by the user. Keep it simple — no rule engine.

Suggested schema (Developer confirms):

```
transaction_rules
  user_id
  name                    (string, optional label)
  enabled                 (boolean, default true)
  priority                (integer, default 0; higher = more specific, wins)
  category_id             (integer, nullable action target)
  money_source_id         (integer, nullable action target)
  tag                     (string, nullable action target, free-form)
  merchant_contains       (string, nullable condition)
  description_contains    (string, nullable condition)
  money_source_id_condition (nullable)
  amount_gt               (decimal, nullable condition)
  amount_lt               (decimal, nullable condition)
  timestamps
```

- Condition selectors: `condition_field` (merchant|description|money_source|amount)
  + `condition_value`; represented by nullable columns above for simplicity.
- Actions: zero or more of `category`, `tag`, `money_source`. Rule matching is
  an `AND` of the set conditions; actions with values are applied.

### Rule precedence (documented behavior)

When multiple rules match a transaction:

1. Amount conditions (most specific) — then
2. Money Source + merchant combination — then
3. Merchant rule — then
4. Generic description rule.

Within the same tier, the rule with the highest `priority`, then most recently
updated, wins for any conflicting action. Non-conflicting actions from multiple
matching rules can both apply (e.g., one sets category, another adds a tag).

### Execution & duplicate prevention

- Apply rules on expense/income **create** (manual, CSV import, Gmail import
  via `Expenses::Create`) and on Gmail sync. Do NOT auto re-apply on every
  update — only when a transaction is created or when a user explicitly triggers
  "Apply rules" (optional) or edits an uncategorized/new transaction.
- Track application to avoid repeat work: store `applied_rule_ids` (JSON) on
  the Transaction, plus `rule_id` for the winning category rule. A rule's
  category action is applied once; tag actions only if the tag isn't already
  present. Manual overrides never get clobbered (a rule matches on
  create/import only — after the user edits, rules do not re-run).
- Rule actions never overwrite an explicit user selection present at creation
  time; rules fill gaps (blank category, no matching tag) but do not replace
  non-blank values unless configured (default: do not overwrite).

### Suggested rules (deterministic, no AI)

- On the Rules index, show a **"Suggested rules"** panel computed from the
  user's transaction history:
  - A merchant text appears in ≥ 5 transactions AND ≥ 90% share the same
    category → suggest `<merchant> → <category>`.
  - A merchant was repeatedly manually corrected to the same category (≥ 3
    corrections; track corrections via a lightweight history/aggregate) →
    suggest "Always categorize X as Y?".
- Each suggestion is dismissible and has a **Create rule** button (opens the
  same rule builder prefilled). Never auto-create.

---

## 3. Main page — Rules index

Layout: page header + two sections on one page.

### Page header

```
<div class="d-flex justify-content-between align-items-center mb-4 flex-wrap gap-2 d-print-none">
  <h1><i class="bi bi-magic me-2"></i>Rules</h1>
  <div class="d-flex gap-2">
    <button class="btn btn-outline-secondary disabled" disabled> <i class="bi bi-lightbulb"></i> Suggestions (<count>) </button>
    <a href="#/rules/new" class="btn btn-primary"><i class="bi bi-plus-lg me-1"></i>New rule</a>
  </div>
</div>
```

- Helper text under header (small, muted): "Rules automatically categorize your
  transactions when they're added or synced. You can change anything afterwards."

### Section 1 — Suggested rules (contextual, above the list)

Card `card shadow-sm` with header "Suggested rules" + `bi-lightbulb`, `text-body-secondary`
body. If none: hide section entirely.

Each suggestion row (list-group or stacked rows, `border rounded p-3`):

```
[icon] SMARTFIT  →  [Fitness badge]
  "17 transactions in Fitness"
  [Create rule]  [Dismiss]        ← btn btn-sm btn-primary / btn-outline-secondary
```

And the correction variant:

```
"Always categorize SMARTFIT as Fitness?"
  "Based on 4 recent corrections"
  [Create rule]  [Not now]
```

### Section 2 — Your rules

Summary line (muted small): "4 rules enabled of 5."

Responsive card grid `row g-3`, `col-12 col-md-6 col-lg-4`, each `card h-100 shadow-sm`.
Rules disabled render with reduced opacity (`opacity-75`) and a "Disabled" badge.

Each rule card:

```
card-body
  d-flex justify-content-between align-items-start
    <div>
      <h5 class="card-title mb-1">SMARTFIT</h5>            ← name / merchant label
      <span class="badge bg-success">Enabled</span> or <span class="badge bg-secondary">Disabled</span>
    </div>
    <div class="form-check form-switch">                   ← toggle
      <input class="form-check-input" type="checkbox" role="switch" checked>
    </div>

  <div class="badge bg-light text-dark border me-1"><i class="bi bi-shop me-1"></i>Merchant contains</div>
  <code class="fw-bold">SMARTFIT</code>

  <hr>

  <div class="mb-1 small">
    <i class="bi bi-arrow-right text-primary me-1"></i>Category → <span class="category_badge">Fitness</span>
  </div>
  <div class="mb-1 small">
    <i class="bi bi-arrow-right text-primary me-1"></i>Tag → <span class="badge bg-light text-dark"><i class="bi bi-tag me-1"></i>Subscriptions</span>
  </div>

card-footer bg-transparent
  d-flex justify-content-end gap-2, btn-group btn-group-sm
    Edit   btn btn-outline-primary   bi-pencil
    Delete btn btn-outline-danger    bi-trash  (button_to, data confirm "Delete this rule?")
```

- **Card title** uses the rule name if present, else the merchant/description
  condition value.
- The "Cuando" line reads human: `When the merchant contains "SMARTFIT"`.
- Action lines read: `Category → Fitness`, `Tag → Subscriptions`,
  `Money source → Nubank`.

### Empty state (no rules, no suggestions)

Same pattern as budgets index empty state:

```
card shadow-sm > p-5 text-center
  <i class="bi bi-magic display-4 text-muted mb-3 d-block"></i>
  <h4>No rules yet</h4>
  <p class="text-muted">Create a rule to categorize repeating transactions automatically.</p>
  <a class="btn btn-primary mt-3"><i class="bi bi-plus-lg me-1"></i>Create your first rule</a>
```

---

## 4. New / Edit rule — builder

Single card form (`card shadow-sm`, `col-md-8 mx-auto`), page header "New rule" /
"Edit rule". Uses progressive disclosure — starts with one condition + one
action, "Add" to reveal more.

### Page header

```
<h1><i class="bi bi-magic me-2"></i>New rule</h1>
```
(with Back link in header row: `btn btn-outline-secondary`, `bi-arrow-left`)

### Form (`form_with`)

**Step label "When"** (`fw-semibold mb-2`, `bi-arrow-right-circle`):

Condition row (repeatable, at least 1):

```
<row g-2 align-items-end>
  <col-12 col-md-4>  WennBedingung select:
      Merchant contains       → "Merchant contains"
      Description contains    → "Description contains"
      Money source is         → "Money source is"
      Amount greater than     → "Amount greater than"
      Amount less than        → "Amount less than"
  <col-12 col-md-6>  value input:
      text input (form-control) for contains / source
      `input-group` with `$` + number input for amount
```

Human-language micro-copy beside each field (`small text-muted`).

**Step label "Then"** (`fw-semibold mt-4 mb-2`, `bi-arrow-right-circle`):

Action row (repeatable, at least 1):

```
<row g-2 align-items-end>
  <col-12 col-md-4>  action select: Category | Tag | Money source
  <col-12 col-md-6>  value:
      category → collection_select of categories (with badge preview)
      tag      → text input "Subscriptions" (free-form)
      money_source → collection_select of sources
  <col-12 col-md-2>  remove button (bi-x-circle, only if > 1 action)
```

**Add action** link below (progressive disclosure), `btn btn-link p-0`,
`bi-plus-circle` + "Add action".

**Name (optional)** field: `form-control`, placeholder "e.g. Gym memberships".

**Priority (advanced, hidden)** — collapsed `details` element:
"Precedence (optional)" — help text: "When multiple rules match, the most
specific wins. Adjust only if needed." Number input. Kept out of the way —
not shown in the default collapsed state.

**Rule type** toggle to indicate expense vs income? First version: goal is
expense categorization; keep the rule generic (matches by merchant/description
regardless of kind), no explicit kind selector to stay simple. Developer can
add `kind` scope later.

**Enabled** switch at bottom: `form-check form-switch`, default on.

**Buttons** (card footer):
- Save: `btn btn-primary`, `bi-check-lg`
- Cancel: `btn btn-outline-secondary`, back

**Validation** via `field_class`/`field_error` (`is-invalid` + helper text).
At least one condition and one action with values required.

---

## 5. Interactions

- **Toggle (switch)**: `patch :toggle_active` per rule, optimistic UI /
  Turbo. Updates Enabled/Disabled badge immediately.
- **Delete**: `button_to` with `data: { confirm: "Delete this rule?" }`, red
  trash icon.
- **Edit**: navigates to edit form prefilled.
- **Suggested → Create rule**: opens New rule with the suggested condition +
  action prefilled and focus on first field.
- **Discount suggestion**: dismisses row (local state / dismiss the
  suggestion record), toolbar count updates.

## 6. States

| State | Handling |
|---|---|
| Empty | Friendly card + CTA (section 3) |
| No suggestions | Section hidden entirely |
| Loading | Turbo defaults (no extra UI needed) |
| Error | `alert alert-danger` flash + inline `is-invalid` field errors |
| Success (create/edit/delete/toggle) | `alert alert-success` flash |
| Disabled rule | `opacity-75` card + `badge bg-secondary "Disabled"` |

## 7. Responsive behavior

- Cards: `col-12 col-md-6 col-lg-4` grid (single column on mobile).
- Rule builder: stacked `col-12` on mobile; `col-md-4`/`col-md-6` labels and
  inputs on ≥md.
- Page header wraps (`flex-wrap gap-2`); button stack below title on small
  screens.

## 8. Accessibility

- Toggle switch: visible `<label>` with screen-reader text "Enable/disable rule
  NAME".
- Icon buttons: `aria-label` (e.g. "Edit rule SMARTFIT", "Delete rule SMARTFIT").
- Form fields: associated `<label>` for every select/input (`form-label`).
- Suggested "Create rule"/"Dismiss" buttons: real `<button>`/`<a>` elements.
- Color not the only signal: Enabled/Disabled also conveyed by text badge, not
  just the switch.
- Contrast: use default Bootstrap badge/button palettes already in app.

## 9. Implementation notes (for Developer)

- Reuse `category_badge` helper, `field_class`, `field_error`, `.summary-value`
  not needed here. No new frameworks.
- Suggested-rules computation lives in a service
  (`TransactionRuleSuggestionService`), deterministic SQL/aggregates — no AI.
- Rule application hooks into `Expenses::Create` and the Gmail importer path;
  gate behind rule existence to avoid overhead.
- `applied_rule_ids` JSON on Transaction prevents duplicate application;
  manual edits clear/require re-confirm only when explicitly invoked.
- Write feature/request specs: creation, edit, delete, enable/disable,
  merchant & description matching, category & tag & money-source actions,
  multiple conditions, multiple matching rules (precedence), manual override,
  imported + Gmail transactions, duplicate-application prevention, suggested
  rules (deterministic + correction-based), dismiss.
