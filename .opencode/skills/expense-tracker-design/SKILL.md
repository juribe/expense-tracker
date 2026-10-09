---
name: expense-tracker-design
description: UI/UX design conventions (Bootstrap 5.3 → Spike theme, ERB views, cards, forms, badges, money formatting, HTML mockups) for the Expense Tracker Rails app. Use when creating or modifying views, layouts, HTML mockups, design specs, forms, or any UI component in the expense-tracker project.
---

# Expense Tracker Design System

Conventions after the 2026 Spike-theme redesign. Follow them exactly; do not
introduce new frameworks, icon sets, or design tokens.

## Stack

- Rails 8 + ERB views, Turbo (use `turbo_method` for non-GET linkssell)
- **Spike admin theme, vendored**: `app/assets/vendor/themes/spike.css`
  (compiled Bootstrap 5.3.2 + Tabler icons + dark mode + skins, loaded via
  `stylesheet_link_tag "themes/spike"`)
- Tabler icons via the vendored font: `<i class="ti ti-<name>">` — never
  `bi …` (Bootstrap Icons is removed); mapping kept during migration:
  e.g. `bi-plus-lg→ti-plus`, `bi-trash→ti-trash`, `bi-pencil→ti-pencil`,
  `bi-piggy-bank→ti-pig-money`, `bi-check-circle→ti-circle-check`
- The design system lives in `app/assets/stylesheets/theme.css` (tokens,
  surfaces, components). Per-need page CSS: `dashboard.css`, `expenses.css`,
  `reports.css`, `financial_chat.css`, `playground.css` + domain styles in
  `application.css` (loan/account/credit-card/budget/recognition cards).
- NO Tailwind, no Sass build, no JS frameworks. Vanilla JS only.

## Themes and dark mode

- `<html data-bs-theme="light|dark" data-color-theme="Blue_Theme" data-layout="vertical">`
- Everything must adapt to dark mode via Bootstrap variables / `[data-bs-theme=dark]` blocks in theme.css. Verify both themes for new markup.
- `app/assets/javascripts/shell.js` owns: theme toggle (`[data-theme-toggle]`,
  persisted `localStorage.etTheme`), sidebar (full/mini/off-canvas with
  `data-sidebartype`, persisted `etSidebarMini`, mobile `show-sidebar`).

## Chrome and navigation

- Layout: `application.html.erb` → `#main-wrapper → aside.left-sidebar → .page-wrapper → header.topbar → .body-wrapper → .app-container`
- Topbar partial: `shared/_topbar.html.erb` (cycle indicator, alerts bell, theme toggle, user dropdown incl. dev tools)
- Sidebar partial: `shared/_sidebar.html.erb` — Spike classes
  (`sidebar-item/sidebar-link/aside-icon/hide-menu/nav-small-cap/collapse.first-level`),
  grouped per domain: Inicio / Actividad / Dinero / Planificación / Deudas /
  Análisis / Por revisar / Automatización. Active state server-rendered.

## Global design rules

1. Semantic colors only: green = income/positive/healthy, red = expense/debt,
   blue = accounts/neutral, amber = attention, gray = secondary. Classes:
   `amt-pos`, `amt-debt`, `text-balance-blue`, `delta-badge(-success|-danger)`.
2. Money: `money_field_value` helper for inputs; `number_to_currency` for
   display; amounts are bold `num` (tabular-nums) and carry meaning.
3. Page header: `<%= render "shared/page_header", title:, subtitle: do — actions
   end %>`; never child h1 + button row ad hoc. Card titles: `h5.card-title`.
   Section labels: `.section-title`; KPI blocks: `shared/_stat` (never colored
   "giant metric cards").
4. Lists: `shared/_section` (card with header), `ledger-table` table treatment
   (`cell-strong/cell-muted/cell-amount`), `shared/_empty_state` for empties.
5. Surfaces: `.card` has `1px` border + `.75rem` radius, no shadow. Interactive
   cards: `card-hover`. Debt cards: `card-debt` red accent.
6. Forms: `form-section` + `form-section-title` for grouped sections;
   `field_class`/`field_error` for validation; submit = `btn btn-primary`,
   cancel = `btn btn-outline-secondary`.
7. Filters: `.filter-chip` (with `.active`), grouped rows; complex filters top
   of the page in a card, secondary filters may collapse.
8. Charts stay Chartkick/Chart.js with the semantic palette.

## Money sources (accounts/cards)

- Kinds: `source_kind_icon` maps to ti- icons (building-bank, credit-card,
  cash, wallet, pig-money, coin). Distinct card components:
  `_account_card` / `_credit_card_card` / `_loan_card`.
- Credit-card surfaces show: balance, limit, utilization bar, statement/due day.

## State to design for (every screen)

- Empty (with CTA), error (danger alert + invalid fields), success (green
  alert), loading (Turbo/Bootstrap defaults), and mobile (`col-12` first,
  `d-none d-md-*` secondary columns; `.mobile-list` pattern in expenses).
- Keep `data-testid` attributes — Playwright and Capybara assertions depend on
  them (see `test/` and `playwright/`).

## HTML mockups (design stage)

- Self-contained HTML that references the vendored Spike + theme CSS is NOT
  possible offline; mockups keep using CDN Bootstrap 5.3 + Tabler webfont and
  mirror theme.css tokens inline. Output body content only.

## Rules

1. Reuse existing views and helpers as templates before inventing markup.
2. Keep UI copy in English or Spanish consistent with the current locale files
   (Spanish defaults).
3. Never add CSS/JS frameworks or files; extend `theme.css` (design tokens) or
   the page-specific css files.
4. New view helpers go in `ApplicationHelper` (or a matching
   `<Resource>Helper`), never inline logic in views.
