**Recurring Transactions UI – Design Spec (Bootstrap 5)**  

1. **Page Layout** – `container-fluid py-4` with a top **breadcrumb** (`breadcrumb mb-3`) and a **page title** (`h4.text-primary`).  
2. **Tabs Navigation** – `nav nav-tabs mb-4` → “Income” & “Expense” tabs (`nav-link`, active tab `active`).  
3. **Add Button** – Right‑aligned `btn btn-success ms-auto` (“Add Recurring”) opens the **Create Form** modal.  
4. **Recurring Table** – `table table-hover align-middle` inside `table-responsive`. Columns: Category, Description, Amount, Day, Last Received/Pay, Status, Actions.  
5. **Status Badge** – `badge bg-success` = **Pending**, `badge bg-secondary` = **Completed**, `badge bg-danger` = **Inactive**.  
6. **Action Buttons** – `btn btn-outline-primary btn-sm me-1` (Edit), `btn btn-outline-danger btn-sm me-1` (Delete/Deactivate), `btn btn-primary btn-sm` (Receive/Pay).  
7. **Create/Edit Modal** – `modal fade` → `modal-dialog modal-lg`. Form uses `row g-3` with Bootstrap inputs:  
   - Category: `select.form-select` (required)  
   - Description: `input.form-control`  
   - Amount: `input.form-control` (`type="number"` step="0.01")  
   - Payment Day: `input.form-control` (`type="number"` min 1 max 31)  
   - Type (Income/Expense): `select.form-select` (only in Create)  
   - Active toggle: `form-check form-switch` (`input.form-check-input`).  
8. **Modal Footer** – `btn btn-secondary` (Cancel) & `btn btn-primary` (Save). Validation feedback via `invalid-feedback`.  
9. **Receive/Pay Confirmation Modal** – `modal-sm` with:  
   - Header: `modal-title` (“Confirm Receive” / “Confirm Pay”).  
   - Body: read‑only fields for Category, Description, Configured Amount (`form-control-plaintext`).  
   - Date picker: `input.form-control` (`type="date"` default = today).  
   - Amount override: `input.form-control` (pre‑filled, editable).  
   - Footer: `btn btn-outline-secondary` (Back) & `btn btn-success` (Confirm).  
10. **Success Toast** – `toast align-items-center text-bg-success border-0` appears top‑right after processing, auto‑hide after 3 s.  
11. **Error Toast** – `toast text-bg-danger` for validation or duplicate‑processing errors.  
12. **Empty State** – centered `div.text-center py-5` with `svg` icon, `h5` (“No recurring transactions yet”), and `btn btn-outline-primary` (“Add your first”).  
13. **Responsive Behavior** – Table collapses on `<md` via `d-none d-md-table-cell` for less‑important columns (Last Received, Actions remain).  
14. **Color Palette** – Primary: `#0d6efd` (Bootstrap default), Success: `#198754`, Danger: `#dc3545`, Neutral text: `#212529`.  
15. **Hover/Focus** – Table rows use `table-hover`; buttons use `hover` state (`btn-primary:hover` → darker shade).  
16. **Accessibility** – All inputs have associated `<label>`; modals trap focus; `aria-live="polite"` on toasts.  
17. **Interaction Flow**  
    - Click **Add Recurring** → open Create Modal → Save → table refresh.  
    - Click **Edit** → pre‑filled Edit Modal → Save → update row.  
    - Click **Delete/Deactivate** → confirm `confirm()` → soft‑delete → status badge → “Inactive”.  
    - Click **Receive/Pay** → open Confirmation Modal → adjust date/amount → Confirm → create one‑time transaction, update **Last Received/Pay**, set status to **Completed** for current month, show Success Toast.  
18. **Prevent Duplicate** – After processing, button switches to disabled `btn btn-outline-secondary disabled` with tooltip “Already processed this month”.  
19. **Pagination** – `nav` with `pagination pagination-sm` below table if >10 rows.  
20. **Search & Filter** – `input-group` (`form-control` + `btn btn-outline-secondary`) for quick text search; dropdown filter for Category and Status.  

*All components follow the existing Bootstrap 5 theme and reuse the app’s global SCSS variables.*