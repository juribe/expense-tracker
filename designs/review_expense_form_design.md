**Expense Form – UI/UX Design Spec (Bootstrap 5)**  

| # | Specification |
|---|---------------|
| 1 | **Layout** – `<section class="container py-4">` → `<form class="row g-3 needs-validation" novalidate>` |
| 2 | **Title** – `<h2 class="col-12 text-primary mb-3">Add New Expense</h2>` |
| 3 | **Date Picker** – `<input type="date" class="form-control" id="expenseDate" required>` |
| 4 | **Category Selector** – `<select class="form-select" id="category" required>` (options loaded from API). |
| 5 | **Amount Input** – `<input type="text" class="form-control" id="amount" placeholder="0.00" required pattern="^\d+(\.\d{1,2})?$">` |
| 6 | **Currency Switch** – `<select class="form-select" id="currency" required>` (USD, EUR, GBP, …). Auto‑convert preview shown beside amount. |
| 7 | **Description** – `<textarea class="form-control" id="description" rows="3" placeholder="Optional details"></textarea>` |
| 8 | **Receipt Upload** – `<input class="form-control" type="file" id="receipt" accept="image/*,application/pdf">` |
| 9 | **Upload Preview** – `<div id="receiptPreview" class="mt-2"></div>` (shows thumbnail or PDF icon). |
|10| **Submit Button** – `<button type="submit" class="btn btn-primary d-flex align-items-center"><span>Save Expense</span></button>` |
|11| **Cancel Link** – `<a href="#" class="btn btn-link text-muted">Cancel</a>` (returns to dashboard). |
|12| **Validation** – Use Bootstrap’s `.was-validated` + custom JS. Show `<div class="invalid-feedback">` per field (e.g., “Amount must be a number”). |
|13| **Error Handling** – On API failure, display a dismissible `<div class="alert alert-danger alert-dismissible fade show">` with retry button. |
|14| **Success State** – Show `<div class="alert alert-success">Expense saved successfully.</div>` and reset form. |
|15| **Loading State** – While submitting, disable all inputs, replace button text with `<span class="spinner-border spinner-border-sm me-2"></span>Saving…`. |
|16| **Edge Cases** – • Missing required fields → inline errors. <br>• Currency mismatch → auto‑convert using stored rates, display warning if rate > 24 h old. <br>• Large file (>5 MB) → reject with “File too large”. |
|17| **Responsive** – On ≥ md screens: two‑column layout (`.col-md-6` for date & amount, `.col-md-6` for category & currency). On smaller screens stack full width. |
|18| **Colors** – Primary: `#0d6efd` (Bootstrap default). Secondary: `#6c757d`. Error: `#dc3545`. Success: `#198754`. Use `.bg-light` for form background. |
|19| **Accessibility** – All inputs have associated `<label for="">`. ARIA live region for validation messages. Keyboard‑navigable, focus outline visible. |
|20| **Documentation** – Spec stored at `designs/expense_form_spec.md`; mockup at `mockups/expense_form.html`. |

*All components use native Bootstrap 5 classes; custom JS only for validation, currency conversion, and file preview.*