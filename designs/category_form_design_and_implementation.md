**Category Form – UI/UX Design Specification (Bootstrap 5)**  

1. **Form Container** – `container-fluid py-4` with max‑width `960px`, centered via `mx-auto`.  
2. **Card Wrapper** – `card shadow-sm border-0`; header `card-header bg-primary text-white` titled **“Create / Edit Category”**.  
3. **Responsive Grid** – Inside `card-body`, use `row g-3`; each field occupies `col-12 col-md-6` (two‑column on ≥768 px).  
4. **Category Name** – `label` with `form-label` (required *). Input: `input type="text" class="form-control" placeholder="e.g., Electronics"`; `aria-describedby="nameHelp"`.  
5. **Slug (auto‑generated)** – Same layout; disabled input: `class="form-control-plaintext bg-light"`; tooltip `title="Auto‑generated from name"` .  
6. **Parent Category** – `select` with `class="form-select"`; first option “None (Root)” disabled `selected`.  
7. **Description** – `textarea` `class="form-control" rows="3"`; placeholder “Optional detailed description”.  
8. **Status Toggle** – Inline switch: `div class="form-check form-switch"` → `input type="checkbox" class="form-check-input"`; label “Active”.  
9. **Image Upload** – `div class="input-group"` → `input type="file" class="form-control"` + `button class="btn btn-outline-secondary"` labeled “Browse”. Preview thumbnail `img class="img-thumbnail d-none mt-2"` toggled on file select.  
10. **Action Buttons** – Footer `card-footer d-flex justify-content-end gap-2`:  
    - **Cancel** – `button type="button" class="btn btn-outline-secondary"` → close modal / navigate back.  
    - **Save** – `button type="submit" class="btn btn-primary"` (disabled until form dirty & valid).  
11. **Validation States** –  
    - **Invalid**: `input.is-invalid`, `select.is-invalid`; show `<div class="invalid-feedback">` under field.  
    - **Valid**: `input.is-valid`, `select.is-valid`; optional `<div class="valid-feedback">Looks good!</div>`.  
12. **Error Summary** – Top of form `alert alert-danger d-none` toggled on submit with list of error messages.  
13. **Success Toast** – `div class="toast align-items-center text-bg-success border-0"` triggered on successful save, auto‑hide after 3 s.  
14. **Focus & Hover** – Use default Bootstrap focus ring (`:focus-visible`); buttons darken `bg-primary` → `bg-primary-hover` via `hover` state.  
15. **Accessibility** – All inputs have associated `<label for="">`; error messages linked via `aria-describedby`; contrast meets AA.  
16. **Mobile Behavior** – Single‑column layout (`col-12`) on <768 px; touch‑friendly tap targets ≥44 px.  
17. **Print Styles** – Hide interactive elements (`.form-switch`, `.input-group`, buttons) using `d-print-none`.  
18. **Theming** – Primary color `#0d6efd`, secondary `#6c757d`; error `#dc3545`; success `#198754`.  
19. **Spacing** – Consistent `gap-3` between rows; `mb-3` on each form group.  
20. **Iconography** – Use Bootstrap Icons: `bi-exclamation-circle` in invalid feedback, `bi-check-circle` in valid feedback.  

*All classes are native Bootstrap 5; no custom CSS required beyond project‑wide variables.*