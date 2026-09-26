---
name: expense-tracker-design
description: UI/UX design conventions (Bootstrap 5, ERB views, cards, forms, badges, money formatting, HTML mockups) for the Expense Tracker Rails app. Use when creating or modifying views, layouts, HTML mockups, design specs, forms, or any UI component in the expense-tracker project.
---

# Expense Tracker Design System

Conventions extracted from the live app. Follow them exactly; do not
introduce new frameworks, icon sets, or design tokens.

## Stack

- Rails 8 + ERB views, Turbo (use `turbo_method` for non-GET links)
- Bootstrap 5.3 via CDN (already loaded in the layout - never re-add it)
- Bootstrap Icons 1.10 via CDN (`bi bi-<icon>`)
- NO Tailwind, NO custom CSS files, NO JavaScript frameworks. The only
  custom CSS is the small `<style>` block in
  `app/views/layouts/application.html.erb`.

## Global chrome (application.html.erb)

- Navbar: `navbar navbar-expand-lg navbar-dark bg-primary shadow-sm`,
  brand uses `bi bi-wallet2` + bold text (`navbar-brand` override)
- Content wrapper: `<main class="container py-4">`
- Flash: dismissible `alert alert-success` (notice) / `alert-danger` (alert)
- Existing CSS overrides (already global, reuse them):
  - `body { background: #f8f9fa; }`
  - `.card { border: none; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }`
  - `.btn { border-radius: 8px; }`
  - `.summary-value { font-size: 2rem; }`

## Page header pattern

```erb
<div class="d-flex justify-content-between align-items-center mb-4 d-print-none">
  <h1><i class="bi bi-wallet2 me-2"></i>Page Title</h1>
  <div class="d-flex gap-2">
    <%= link_to new_thing_path, class: "btn btn-primary" do %>
      <i class="bi bi-plus-lg me-1"></i>New Thing
    <% end %>
  </div>
</div>
```

Primary create action: `btn btn-primary` with `bi-plus-lg`. Secondary
actions: `btn btn-outline-primary`.

## Index/list pages

- Responsive card grid: `row g-3`, columns `col-12 col-md-6 col-lg-4`,
  cards `card h-100 shadow-sm`
- Row actions use icon-only small buttons in `btn-group btn-group-sm`:
  edit = `btn btn-outline-primary` + `bi-pencil`,
  delete = `btn btn-outline-danger` + `bi-trash` via `button_to`
  with `data: { confirm: "Are you sure?" }`
- Always include an empty state (friendly message + call-to-action button)

## Money and amounts

- Amounts are bold and colored by meaning: `text-success` for
  positive/assets/income, `text-danger` for credit cards/expenses/negatives
- Format values with the `money_field_value` helper (2 decimals,
  `,` delimiter, no trailing zeros)
- Large summary numbers use the `.summary-value` class

## Badges and icons

- Category badges: `category_badge(category)` helper (rotates
  `CATEGORY_COLORS`: primary success danger warning info secondary dark)
- Identifier/tag style badges: `badge bg-light text-dark` with a `bi` icon
- Icons carry meaning; add spacing with `me-1`/`me-2`
- Kind-to-icon mappings (e.g. `source_kind_icon`: account→bank,
  debit_card→credit-card, credit_card→credit-card-2-front, cash→cash,
  wallet→wallet2) belong in `ApplicationHelper`, not in views

## Forms

- Inputs: `form-control`; selects: `form-select`
- Validation: use the `field_class(object, method)` helper
  (`is-valid`/`is-invalid`) and `field_error(object, method)` for messages
- Prefill money inputs with `money_field_value`
- Submit button: `btn btn-primary`; cancel/back: `btn btn-outline-secondary`

## Navigation

- Mark the active nav item with the `active_class('controller')` helper

## States to design for (every screen)

- Empty (with CTA), error (danger alert + invalid fields), success
  (green alert), loading (Turbo/Bootstrap defaults), and mobile
  (`col-12` first, then `col-md-*`/`col-lg-*`)

## HTML mockups (design stage)

- Self-contained HTML file using the same Bootstrap + Icons CDNs and the
  same `<style>` overrides as the layout
- Include the navbar and realistic sample data
- Output body content only - the boilerplate (head/footer) is added by
  the caller

## Rules

1. Reuse existing views and helpers as templates before inventing markup.
2. Keep UI copy in English (code comments may be Spanish).
3. Never add CSS/JS frameworks or files; extend the layout `<style>`
   block only when a rule is truly global.
4. New view helpers go in `ApplicationHelper` (or a matching
   `<Resource>Helper`), never inline logic in views.
