**Monthly Expenses UI Spec (Bootstrap 5 – ≤30 lines)**  

1. **Page Layout** – `container-fluid > row > col-12` with a page header (`h1`) and a top‑right “Add Expense” button (`btn btn-primary`).  

2. **Header Bar** – `d-flex justify-content-between align-items-center mb-4` containing:  
   - Title “Monthly Recurring Expenses”  
   - “Add Expense” (`btn btn-primary ms-2`).  

3. **Monthly Expenses Table** – `table table-hover align-middle` inside a responsive wrapper (`table-responsive`). Columns:  
   - **Category** (`text-capitalize`)  
   - **Description** (`text-truncate`)  
   - **Monthly Amount** (`text-end fw-medium`)  
   - **Payment Day** (`text-center`)  
   - **Last Payment** (`text-center`)  
   - **Status** (`text-center`) – badge (see 5)  
   - **Actions** (`text-center`) – icon buttons.  

4. **Status Badges** – `badge` component:  
   - **Pending** – `badge bg-warning text-dark` (tooltip “Due this month”).  
   - **Paid** – `badge bg-success` (tooltip “Paid on <date>”).  

5. **Action Buttons (per row)** – `btn btn-sm btn-outline-secondary me-1` with Font Awesome icons:  
   - **Edit** – `fa‑solid fa‑pen` → opens Edit Modal.  
   - **Delete** – `fa‑solid fa‑trash text-danger` → confirms via `modal`.  
   - **Pay** – `fa‑solid fa‑credit‑card btn-success` (shown only when status = Pending).  

6. **Create / Edit Monthly Expense Modal** – `modal fade` → `modal-dialog modal-lg`. Form fields (Bootstrap `form-floating`):  
   - Category (select) – `form-select`.  
   - Description (text) – `form-control`.  
   - Monthly Amount (number, step 0.01) – `form-control`.  
   - Payment Day (number 1‑31) – `form-control`.  
   - Active toggle – `form-check form-switch`.  
   - Footer: “Save” (`btn btn-primary`) & “Cancel” (`btn btn-outline-secondary`).  

7. **Pay Confirmation Modal** – `modal fade` → `modal-dialog`. Content:  
   - Header: “Confirm Payment – <Category>”.  
   - Body:  
     - Payment Date – `input type="date"` pre‑filled with current month + payment_day.  
     - Amount – `input type="number"` pre‑filled with monthly amount, editable.  
     - Optional note – `textarea`.  
   - Footer: “Confirm Payment” (`btn btn-success`) & “Cancel” (`btn btn-outline-secondary`).  

8. **Interaction Flow**  
   - **Add/Edit** → open modal → client‑side validation → `POST/PUT` → on success close modal & refresh table.  
   - **Delete** → open simple confirm modal → `DELETE` → on success fade‑out row.  
   - **Pay** → open Pay modal → validate date not already paid for that month → on “Confirm” send `POST /monthly_expenses/:id/pay` → on success:  
     * add new row to regular Expenses list (outside scope)  
     * update **Last Payment** cell, change **Status** badge to “Paid”.  

9. **Responsive Behavior** – Table scrolls horizontally on `<768px`; modal forms stack (`col-12`).  

10. **Colors & Theme** – Use app’s primary (`#0d6efd`) for buttons, warning badge (`#ffc107`), success badge (`#28a745`), danger text for delete icon (`#dc3545`). All text on white background, subtle `bg-light` row hover.  

11. **Accessibility** – All icons have `aria-label`; modals trap focus; `role="status"` on badges.  

12. **Empty State** – If no monthly expenses, show centered `alert alert-info` with “No recurring expenses yet. Click ‘Add Expense’ to get started.”  

---  
*All components reference Bootstrap 5 classes; icons use Font Awesome 6.*