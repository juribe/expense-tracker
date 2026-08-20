# Expense Views Table — Design Specification

**Task:** Design Expense Views Table (`86e2x46ew`)  
**Surface:** **Operate** (primary) — users scan, filter, sort, and act on expense records. Glanceable totals are secondary, not a marketing hero.  
**Scope:** Redesign `/expenses` (index). Do not change the Add/Edit expense form. Do not add product fields the model does not have.

This replaces the earlier Bootstrap-only notes in this file. Those notes invented merchant, status, payment method, receipts, and multi-currency. Those are **out of this design**.

---

## 1. Existing product (source of truth)

Reuse the live Expense Tracker, not a generic SaaS table.

**Chrome:** Bootstrap 5.3 + Bootstrap Icons. Dark primary navbar (`navbar-dark bg-primary`), body `#f8f9fa`, white cards with light shadow, 8px button radius, page `h1` + primary action on the right.

**Expense model (schema):** `date`, `description`, `amount` (decimal 10,2), `category_id`, `frequency` (`one_time` | `weekly` | `monthly` | `yearly`), `user_id`. No merchant, status, payment method, receipt, or currency column.

**Current index already has:** GET filters (category, start date, end date, frequency), table columns Date / Description / Category / Frequency / Amount / actions, `category_badge`, frequency as `badge bg-secondary`, amount as `fw-bold text-danger` with a leading minus, Edit (`btn-outline-primary`) and Delete (`btn-outline-danger`). Empty copy: “No expenses yet. Add your first one!”

**Gaps vs this task:** column sort, amount-range filter, clear filters, result count, pagination, bulk actions, loading/error/no-results states, row view, keyboard/a11y, defined mobile layout, export of the current result set.

**Related screens:** Dashboard “View all” already links here. Add Expense stays `new_expense_path` (existing form). Categories stay as-is.

---

## 2. User flow

1. User opens **Expenses** (nav or Dashboard → View all).
2. Page loads the current user’s expenses, default sort **date descending**.
3. User optionally filters (category, dates, frequency, amount range) and submits **Filter**. Query string persists the state (shareable / back-button).
4. User sorts by clicking a column header (toggles asc/desc; one active sort).
5. User scans rows. Clicking a row or **View** opens a **details drawer** (read-only). **Edit** goes to the existing edit page. **Delete** opens a confirm modal.
6. User may select rows and **Delete selected**.
7. User may **Export CSV** of the *current filtered + sorted set* (not only the current page).
8. Large sets paginate (page in query string).

---

## 3. Screens

| Screen | Role |
|---|---|
| Expenses index | Only new/changed surface in this task |
| Expense details drawer | Read-only overlay on the index (there is no `expenses/show` view today) |
| Delete confirm modal | Single or bulk |
| Existing New/Edit expense | Unchanged; linked from header / row Edit |
| Empty / no-results / loading / error | States of the same index, not separate routes |

---

## 4. Layout (desktop ≥ 768px)

```
[ Navbar — existing ]
[ h1 Expenses                    ] [ Export CSV ] [ Add Expense ]
[ Filter card: Category | From | To | Frequency | Min $ | Max $ ]
[ Filter ] [ Clear ]
[ “N expenses · $X,XXX.XX”                    page size note ]
[ (bulk bar — only when ≥1 row selected) ]
[ Table ]
[ Pagination ]
```

- Page sits in the existing `main.container.py-4`.
- Header: `d-flex justify-content-between align-items-center mb-4`. Title `h1` with `bi-receipt` (current pattern). Actions: outline **Export CSV**, primary **Add Expense**.
- Filters: existing `card shadow-sm mb-4` GET form, `row g-3`. Add amount min/max. Keep Filter as `btn-outline-primary`. Add **Clear** (`btn-outline-secondary`) that returns to `/expenses` with no query.
- Table in `card shadow-sm` → `table-responsive` → `table table-hover align-middle mb-0` with `thead.table-light`.
- Do not add summary stat cards, hero, or a second filter paradigm. Filters stay a form card, not a slide-over on desktop.

### Mobile (< 768px)

- Header stacks: title, then full-width Add, then Export.
- Filters stay the same form, stacked (`col-12`).
- Table is replaced by a **stacked list** (not horizontal-scroll-only). Each expense is a card-row:
  - Line 1: date (muted) · category badge
  - Line 2: description (or “No description”)
  - Line 3: frequency badge · amount (right, danger, tabular)
  - Actions: View / Edit / Delete, min 44×44 hit target
- Pagination remains below. Bulk select uses a checkbox on each card; bulk bar sticks under the header.

---

## 5. Table columns (desktop)

| Column | Source | Sort | Notes |
|---|---|---|---|
| Checkbox | — | no | Header checkbox = select page. `aria-label="Select expense, {date} {description}"` |
| Date | `expense.date` | yes (default desc) | `%b %d, %Y` (current) |
| Description | `expense.description` | yes | Truncate to 1 line with title tooltip. Empty → muted “No description” |
| Category | `category.name` via `category_badge` | yes | Existing helper colors |
| Frequency | `frequency.humanize` | yes | `badge bg-secondary` |
| Amount | `amount` | yes | Right-aligned, `fw-bold text-danger`, `-$1,234.56` (tabular nums). USD assumed |
| Actions | — | no | View, Edit, Delete. Always visible (do not hide on hover — that fails a11y and touch) |

**Do not add:** Merchant, Status, Payment method, Receipt, currency flags.

Footer row (inside the card, not a fake dashboard): **page subtotal** of visible rows, plus the **filtered total** if pagination is in play: `Showing 1–25 of 128 · Page total $412.10 · Filtered total $3,801.44`.

---

## 6. Components

- **Page header** — existing h1 + actions
- **Filter form** — GET, labels on every control
- **Active filter chips** (optional, below the form when any filter is set) — each chip dismisses that param; “Clear all” is the Clear button
- **Results meta** — count + filtered total
- **Bulk action bar** — appears when selection > 0: “N selected”, Select none, Delete selected
- **Data table / mobile list**
- **Sortable header button** — text + caret; `aria-sort="ascending|descending|none"`
- **Pagination** — Bootstrap `pagination`, prev/next + page numbers
- **Details drawer** — Bootstrap offcanvas, end, width ~400px
- **Delete modal** — existing confirm language, destructive primary
- **Toast / flash** — existing `notice` / `alert` (do not invent a second toast system)

---

## 7. Interactions

### Filter

- Submit via **Filter** (keep current explicit submit; do not auto-fetch on every keystroke — that would change the current GET form behavior without a PO request).
- Invalid range (start > end, or min amount > max amount): HTML5 + server; show field `is-invalid` and a short form alert; do not run the query.
- Persistence: query params `category_id`, `start_date`, `end_date`, `frequency`, `min_amount`, `max_amount`, `sort`, `dir`, `page`.
- Changing filters resets `page` to 1. Changing sort resets `page` to 1. Selection does not persist across pages (assumption).

### Sort

- Sortable columns: `date`, `description`, `category`, `frequency`, `amount`.
- First click on a new column: date/amount default **desc**; text columns default **asc**. Second click toggles.
- One sort at a time. Visual: active header `text-primary`, caret `bi-caret-up-fill` / `bi-caret-down-fill`. Inactive: muted `bi-chevron-expand`.
- Server-side sort (current index already loads the full relation; keep sort in SQL).

### Row

- Row click (not on checkbox/buttons) opens details drawer.
- **View:** same drawer. Fields: Date, Amount, Description, Category, Frequency, Created, Updated. Actions in drawer footer: Edit, Delete, Close.
- **Edit:** `edit_expense_path` (existing).
- **Delete:** modal. Confirm → `DELETE` → redirect index with existing flash “Expense was successfully deleted.” Keep current filter query on redirect.

### Bulk

- Appropriate bulk action with current model: **delete only**. No “change status” (no status field).
- Header checkbox selects/deselects all rows **on the current page**.
- Bar: `N selected` + Delete selected. Delete modal copy: “Delete N expenses? This cannot be undone.”
- After success: flash, clear selection, stay on current filters.

### Export

- **Export CSV** downloads the current filtered + sorted set (all matching rows, not one page).
- Columns: date, description, category name, frequency, amount.
- Filename: `expenses-YYYY-MM-DD.csv`.
- If the result set is empty, disable Export and set `aria-disabled` + tooltip “Nothing to export”.

### Pagination

- **25 rows per page**, server-side. Not infinite scroll (Rails index + shareable page param).
- Control: prev / numbered / next. Hide when total ≤ 25.
- Deep-link: `page` in query string.

---

## 8. States

| State | UI |
|---|---|
| **Loading** | Keep header + filters. Table body: 8 skeleton rows (`placeholder-wave`). `aria-busy="true"` on the table region. No spinner overlay on top of skeletons. |
| **Empty (no expenses at all)** | Centered block in the card: `bi-inbox` (current), heading “No expenses yet”, body “Add your first one to see it here.”, primary **Add Expense**. Hide pagination, bulk, export disabled. |
| **No results (filters match nothing)** | Distinct from empty: heading “No expenses match these filters”, body “Try clearing a filter or widening the date range.”, **Clear filters** button. Do not show Add as the only action. |
| **Error (index failed)** | `alert alert-danger` above the table: “Couldn’t load expenses.” + **Retry** (reload). Keep filters so the user doesn’t lose input. |
| **Success** | Existing green flash/notice after create/update/delete. |
| **Validation (filters)** | `is-invalid` on the offending inputs; `invalid-feedback` text. |
| **Delete in progress** | Confirm button disabled + spinner; modal stays open until redirect. |
| **Partial bulk failure** | If some deletes fail: danger alert listing count failed; refresh the table. (Implementation detail; UI must show the count.) |

---

## 9. Responsive

| Breakpoint | Behavior |
|---|---|
| ≥ 992px | Full table, all columns, header actions inline |
| 768–991px | Table; Description truncates more aggressively; actions stay icon buttons with `aria-label` |
| < 768px | Stacked list (see §4). Filters stacked. Hit targets ≥ 44px. Do not rely on hover. |

Print: hide checkboxes, bulk bar, and Tweaks; table may print as-is (`d-print-none` on actions is already used on Categories).

---

## 10. Accessibility

- Page `h1` “Expenses”. Table has a visually hidden caption: “Your expenses”.
- Sortable headers are `<button>` inside `<th>`, not clickable `<th>` alone.
- `aria-sort` on the active column.
- Every icon-only button has `aria-label` (Edit {description}, Delete {description}, View {description}).
- Checkboxes labeled. Header checkbox `aria-label="Select all expenses on this page"`.
- Focus visible (`:focus-visible`) on all controls; do not remove Bootstrap focus rings.
- Drawer: focus trap (Bootstrap offcanvas), `aria-labelledby`.
- Modal: `role="dialog"`, labelled, focus on confirm.
- Live region (`aria-live="polite"`) announces “N expenses” after filter/sort.
- Contrast: body text `#212529` on white/gray; amount danger `#dc3545` on white meets 4.5:1 at `fw-bold`; muted `#6c757d` only for secondary text.
- Do not make action icons `opacity-0` until hover.
- Keyboard: Tab through filters → chips → bulk → header checkbox → row checkboxes/actions → pagination. Enter on row opens drawer.

---

## 11. What to implement (engineering)

1. Keep `ExpensesController#index` as the page; add query params for `min_amount`, `max_amount`, `sort`, `dir`, `page`.
2. Fix or replace `Expense.by_category` — the current scope **groups and sums**, so the existing category filter is not a row filter. Index needs `where(category_id:)` (name the scope distinctly, e.g. `in_category`).
3. Load `@categories` on index (today `set_categories` does not run on `index`, but the view already uses `@categories`).
4. Paginate 25; default `order(date: :desc)`.
5. Details: either `show` + offcanvas turbo frame, or a lightweight show payload in the index. Prefer a real `show` action (controller already lists `:show` in `set_expense` but has no action/view).
6. Bulk delete: collection route, IDs from the page, authorize `current_user.expenses`.
7. CSV export: `respond_to` format.csv or `GET /expenses.csv` with the same filters.
8. Preserve filter query string on redirect after delete.
9. `data-testid` on: filter form, table, row, empty, error, pagination (for QA).

---

## 12. Acceptance criteria (UI)

- Table/list is scannable: date, description, category, frequency, amount, actions.
- Filters and sorting are visible and labeled; state lives in the URL.
- Empty, no-results, loading, and error are distinct.
- Responsive behavior is the stacked list under 768px, not “just scroll the table”.
- Designs are implementable from this spec + the HTML mockup without guessing fields.

---

## 13. Assumptions (not PO decisions, but required to ship UI)

- Currency is USD, one currency, as in the current views (`$` / `number_to_currency`).
- Amount min/max is inclusive, in the same units as `expenses.amount`.
- Page size is 25 (not user-configurable in this task).
- Bulk selection is per page only.
- Export is CSV of the filtered set.
- Details drawer is read-only; editing stays on the existing form page.
- Frequency values remain the four existing options.
- Inactive categories may still appear on historical rows; filter dropdown should list categories the user can still filter by (current `Category.all`).

---

## 14. Remaining Product Owner questions

Do **not** block this table on these. They were listed as examples in the ticket; the schema does not support them.

1. Merchant/Vendor — add a field, or keep description as the free-text place?
2. Status (pending/approved) — is there an approval workflow?
3. Payment method — in scope?
4. Receipt attach/indicator — in scope?
5. Multi-currency — in scope?
6. Infinite scroll vs pagination — this design chose pagination; override if needed.
7. Should Export include other formats (XLSX)?

---

## 15. Out of scope

- New visual language (no Inter, no indigo gradients, no glassmorphism).
- Dashboard redesign.
- Add/Edit form redesign.
- Invented columns and approval workflows.
- Figma export / CSS variables beyond what the app already uses.

---

## 16. Mockup

Interactive prototype: `mockups/design_expense_views_table.html`  
Tweaks in the mockup switch Populated / Empty / No results / Loading / Error and do not ship to production.
