# Bulk Update Expense Category and Money Source — Design Specification

**Task:** `86e305qud` — Bulk Update Expense Category and Money Source
**Surface:** **Operate** — extend the existing **Expenses** index (`/expenses`) so users can select multiple expenses and change their Category and/or Money Source in a single action.
**Scope:** Add bulk "Change Category" and "Change Money Source" actions to the existing bulk-selection toolbar on the Expenses index. Reuse the existing per-page selection model. Do not change the Add/Edit form, filters, or the delete flow. Backend endpoint + authorization are specified for the Developer.

---

## 1. Existing product (source of truth)

Reuse the live Expense Tracker, not a generic SaaS table. Current Expenses index already provides:

- **Chrome:** Bootstrap 5.3 + Bootstrap Icons, dark primary **sidebar** layout (see `app/views/shared/_sidebar.html.erb`), body `#f8f9fa`, white `card shadow-sm`, 8px button radius, page `h1` + right-aligned actions.
- **Expense model:** `date`, `description`, `amount`, `category_id`, `money_source_id`, `frequency`, `user_id`. This task touches **`category_id`** and **`money_source_id`** only.
- **Money source:** `MoneySource#display_name` = `"#{name} · #{bank}"`. Kind icons via `source_kind_icon` (`account`→bank, `debit_card`→credit-card, `credit_card`→credit-card-2-front, `cash`→cash, `wallet`→wallet2).
- **Category:** `category_badge(category)` helper (rotating `CATEGORY_COLORS`).
- **Existing bulk selection** (`app/views/expenses/index.html.erb`): per-row checkbox (`.row-check`), header checkbox (`#selectAll` = select all on this page), and a hidden-by-default **bulk bar** (`#bulkBar`) showing `N selected`, `Select none`, and a **Delete selected** button.
- **Translations still on the page:** details drawer (offcanvas), per-row view/edit/delete, filters, sorting, pagination, CSV export, loading skeleton, empty/no-results/error states.

**Gap vs this task:** the bulk bar currently only offers **Delete**. It needs **Change Category** and **Change Money Source** bulk actions with their own confirmation dialogs.

---

## 2. User flow

1. User opens **Expenses** with any filters/search/sort/pagination in place.
2. User checks one or more row checkboxes (`N selected` appears in the bulk bar) or uses the header checkbox to select **all expenses on the current page**.
3. Bulk bar reveals:
   `[ Change Category ] [ Change Money Source ] [ Delete selected ] [ Select none ]` and the running count `12 selected`.
4. **Change Category:** a confirm modal opens showing the count, a **New Category** `form-select` populated with the user's categories, then **Update N Expenses**. Confirm → bulk update → success flash; selection clears; filters/search/sort/page are preserved.
5. **Change Money Source:** same pattern with a **New Money Source** selector from the user's active sources.
6. **Delete selected:** unchanged existing flow.
7. User can clear the selection (`Select none`) or close the modal (`Cancel`) with no changes.

Both changes can also be combined in one operation (see §7 backend contract): selecting **Change Category** then **Change Money Source** can stage both fields before the single confirm/update.

---

## 3. Screens

| Screen | Role |
|---|---|
| Expenses index | Only new/changed surface in this task |
| Change Category confirm modal | New — reusable Bootstrap `modal` |
| Change Money Source confirm modal | New — reusable Bootstrap `modal` |
| Existing delete modal / drawer / filters | Unchanged |
| Success / error flash | Existing `notice` / `alert` in the layout |

---

## 4. Layout (desktop ≥ 992px)

The bulk bar sits directly under the results meta line and above the table card (position already established by the current delete bulk bar). The task says the normal page actions "should remain visible **or** be replaced by the bulk toolbar … depending on the existing design." Current design keeps the header actions (Export CSV / Add Expense) and filters always visible, so **we keep them visible**; only the in-page bulk bar changes.

```
[ Sidebar — existing ]
[ h1 Expenses                        ] [ Monthly Expense ] [ Export CSV ] [ Add Expense ]
[ AI entry card (existing) ]
[ Filter card: Category | Source | From | To | Min $ | Max $   Filter  Clear ]
[ “N expenses · $X”  ·  page size ]
[ Bulk bar — only when ≥1 selected:
     [ 12 selected ]  [ Change Category ] [ Change Money Source ]  [ Select none ] [ Delete selected ] ]
[ Table / mobile list (existing) ]
[ footer totals + pagination (existing) ]
```

- Page sits in the existing `main.container.py-4` (sidebar layout).
- Header actions and filter card are **unchanged**.
- The bulk bar is the **only** element extended. It is a themed bar (`#e7f1ff` background, `#b6d4fe` border) that is `display:none` until selection count > 0.

### Bulk bar composition

- Left: `<strong>N selected</strong>` (bold, primary-tinted) — the live count (uses `aria-live="polite"`).
- Actions, in order:
  1. **Change Category** — `btn btn-sm btn-outline-primary` with `bi-tags` icon.
  2. **Change Money Source** — `btn btn-sm btn-outline-primary` with `bi-wallet2` icon.
  3. `ms-auto` spacer, **Select none** — `btn btn-sm btn-outline-secondary`.
  4. **Delete selected** — `btn btn-sm btn-danger` with `bi-trash`, rightmost (existing).
- Buttons **disabled** when `N = 0`. The bar itself is hidden at `N = 0` anyway.
- On small screens the bar wraps (`flex-wrap`) so the count and actions stack legibly.

### Mobile (< 768px)

- Same `mobile-list` card-rows as today; each card carries its select checkbox.
- Bulk bar stays directly under the filters; wraps to full-width action buttons (44px min hit target). Bar text `N selected` remains the leading element.

---

## 5. Components

- **Bulk bar** — extended existing `#bulkBar` (Bootstrap `d-flex align-items-center gap-2`, `.show` toggles display). New primary actions added between `#clearSel` and `#bulkDelete`.
- **Change Category modal** — Bootstrap `modal modal-dialog-centered`, `modal-title` "Change category for N expense(s)", body contains:
  - a passive summary line (better ICYMI): "You're about to change the category on **N** selected expense(s)."
  - `label` + `select.form-select` **New Category** listing all current user's categories (each option labeled by name; optionally show current category badge of the most common for context — keep simple).
  - `modal-footer`: **Cancel** (`btn btn-outline-secondary`) and **Update N Expenses** (`btn btn-primary`, `bi-check-lg`). Confirm is disabled until a category is chosen.
- **Change Money Source modal** — same structure; label **New Money Source**, options from `current_user.money_sources.active` using `display_name` (option shown with its kind icon, e.g. `<i class="bi bi-bank">`), footer **Cancel** / **Update N Expenses**.
- **Combined update modal (optional but recommended)** — a single modal may hold both a **New Category** and **New Money Source** selector when both bulk actions are invoked; the Developer may reuse the same modal with two fields. At minimum, each action can be confirmed separately.
- **Success flash** — existing layout `alert alert-success`.
- **Error flash / inline** — existing `alert alert-danger`; bulk endpoint errors reported via layout alert, keeping filters intact.

---

## 6. Interactions

### Selection (reuse existing)
- Row checkbox toggles selection; header checkbox selects/deselects **all rows on the current page** (existing behavior — preservation of per-page selection).
- `updateBulk()` recomputes `N selected`, toggles the bar's `.show`, and syncs the header checkbox (already implemented). Extend `updateBulk()` to also disable/enable the two new buttons (they are only ever visible when N>0, so this is defensive).
- **Effect on filters/state:** selecting does **not** navigate. Filters, search, sort, and pagination query params stay in the URL untouched.

### Change Category
1. Click **Change Category** → collect checked row IDs (same mechanism as bulk delete) → stash IDs.
2. Open modal titled `Change category for N expense(s)`; populate **New Category** with `@categories`; pre-select nothing (or a sensible default); **Update N Expenses** disabled until a category is selected.
3. `Cancel` or `Esc` or backdrop → close, no changes, selection unchanged.
4. Confirm → POST bulk update `{ expense_ids: [...], category_id: <id> }` (server-driven; see §7).
5. On success: close modal, clear selection, show flash "**N expenses updated.**", reload the index **preserving current query string**.

### Change Money Source
- Identical flow with **New Money Source** (`money_source_id`) and options from the user's active money sources.

### Combined update
- If a user opens one modal, closes it, then the other, each applies independently. If the implementation offers both fields in one modal, the request sends `{ expense_ids, category_id, money_source_id }` (only present fields are updated — matches §7).

### Delete
- Unchanged existing flow/modal.

### Persistence after update
- After a successful bulk update, redirect back to `/expenses?<existing params>` so **filters, search, sorting, and pagination are preserved**. Clear only the selection.

---

## 7. Backend contract (for the Developer)

**Endpoint:** a collection route, e.g. `PATCH /expenses/bulk_update` (or `POST` compat) mapped to `ExpensesController#bulk_update`.

**Request body:**
```json
{
  "expense_ids": [1, 2, 3, 4],
  "category_id": 10,
  "money_source_id": 5
}
```
- `expense_ids` (required, non-empty). `category_id` **and/or** `money_source_id` — both optional, but at least one required; only provided fields are updated.

**Authorization & validation:**
- Scope updates to `current_user.expenses.where(id: expense_ids)`.
- **Ignore** IDs not owned by the current user (do not error on them, but do not update them; a count of applied vs requested may be surfaced).
- Validate `category_id` belongs to the current user (else 422 with a clear error).
- Validate `money_source_id` belongs to the current user (else 422 with a clear error).
- Reject requests with no IDs, no fields to change, or an empty id list (400/422 with a clear message).
- Never update expenses the user does not own.

**Performance:**
- Perform a single **bulk/database update**: `Expense.where(id: authorized_ids).update_all(category_id:, money_source_id:)` (whichever present) rather than loading/saving each record — efficient for dozens/hundreds of rows.
- Return success with a count of updated expenses; preserve `redirect_to expenses_path(state_query)`.

**Responses:**
- Success → flash notice "**N expenses updated.**" + redirect preserving query state.
- Invalid data / authz failure → `alert` "Couldn't update expenses: <details>" with status 4xx and no partial state change.

---

## 8. States

| State | UI |
|---|---|
| **No selection** | Bulk bar hidden entirely (existing). Header/row checkboxes unchecked. |
| **Selection active** | Bar shows `N selected` + **Change Category** + **Change Money Source** + **Select none** + **Delete selected**. Buttons enabled. |
| **Modal open (select category/source)** | Confirm button disabled until a value chosen; live count in title `Update N Expenses`. |
| **Submitting** | Confirm button shows spinner / `disabled`; modal stays open until response. |
| **Success** | Green layout flash "**N expenses updated.**", selection cleared, filters/sort/page preserved, modal closed. |
| **Error (invalid/unauthorized field)** | Danger alert with message; modal stays open or page alert shown; no data changed. |
| **Validation (no category/source chosen)** | Confirm disabled; `is-invalid` / `invalid-feedback` on the select if submitted empty. |
| **Loading / Empty / No results / Error** | Unchanged existing index states; bulk bar hidden in empty/no-results. |

---

## 9. Responsive

| Breakpoint | Behavior |
|---|---|
| ≥ 992px | Full table + inline bulk bar in a single row |
| 768–991px | Table; bulk bar wraps if needed |
| < 768px | `mobile-list` cards with checkboxes; bulk bar wraps to stacked full-width buttons; targets ≥ 44px |

Print: hide checkboxes and bulk bar (`d-print-none`), matching current behavior.

---

## 10. Accessibility

- Bulk bar is a `region` with `aria-label="Bulk actions"` (existing); count `N selected` in `aria-live="polite"`.
- Header checkbox `aria-label="Select all expenses on this page"`; row checkboxes labeled with the expense (existing).
- Modals: `role="dialog"`, `aria-labelledby` title including the count; focus moves to the select on open; `Esc`/backdrop cancel.
- Every icon button keeps `aria-label` (Change Category, Change Money Source with the count).
- Confirm buttons include the count in their accessible name (e.g. "Update 12 expenses").
- Do not rely on hover; keep `:focus-visible` rings from Bootstrap.
- Contrast: primary-tinted bulk bar text `#0d6efd`/`#084298` on `#e7f1ff` meets thresholds; danger delete unchanged.

---

## 11. What to implement (engineering)

1. Add row + header checkboxes and `N selected` bulk bar is **already present** — extend `updateBulk()` to drive the two new buttons (already shown/hidden together with the bar).
2. Add two new buttons to the bulk bar: **Change Category** (`bi-tags`) and **Change Money Source** (`bi-wallet2`).
3. Add one shared **bulk-edit modal** (or two) with optional **New Category** and/or **New Money Source** selects; prefill from `@categories` and `current_user.money_sources.active`.
4. Wire a `PATCH /expenses/bulk_update` collection route → `ExpensesController#bulk_update`.
5. Controller: authorize via `current_user.expenses`, validate ownership of category/money source, run a single `update_all`, flash result, redirect preserving `state_query`.
6. Collect checked IDs client-side (same path as bulk delete) and POST them with the selected field(s).
7. Clear selection and reload on success; keep the existing query params on the redirect.
8. Add `data-testid` on: bulk bar, change-category button, change-money-source button, both selects, confirm buttons, success/error messages (for QA).

---

## 12. Acceptance criteria (UI)

- Checkboxes select any number of expenses and the bar shows the live `N selected` count.
- **Change Category** and **Change Money Source** each open a confirm modal with the affected count and a user-accessible selector.
- Both fields can be updated together in one bulk operation (combined modal).
- No automatic change without explicit confirmation.
- Success/error messages shown; filters/search/sort/page preserved after the update.
- Bulk actions hidden/disabled when nothing is selected; **Cancel** makes no changes.
- Only the current user's expenses/categories/money sources are touched (authorized on the server).
- Implementation performable as a single bulk `update_all`.

---

## 13. Assumptions

- Selection is **per current page** (existing behavior), matching the current bulk delete.
- All changes require explicit confirmation; nothing auto-applies.
- Money source selector lists **active** sources only (`MoneySource.active`) via `display_name` with kind icon.
- Category selector lists all the user's categories (same set already used by the filter and edit form).
- Currency/new fields: none introduced.

---

## 14. Out of scope

- New selection model that spans pagination/whole result set.
- Changing other expense fields (amount, date, description) in bulk.
- Dashboard, form, filters, or delete-flow redesign.
- New frameworks or design tokens.

---

## 15. Mockup

Interactive prototype: `mockups/bulk_update_expense_category_and_money_source.html` (sidebar chrome, realistic data, working selection + both modals). Prototype-only logic; does not ship to production.
