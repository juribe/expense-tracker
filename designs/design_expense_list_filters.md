**Expense List & Filters – Design Specification**  
*(Bootstrap 5 – v5.3)*  

| # | Element | Layout & Bootstrap Classes | Content / Behavior | Color / Styling |
|---|---------|----------------------------|--------------------|-----------------|
| 1 | **Page Container** | `container-fluid py-4 bg-light` | Full‑width page with vertical padding | Light gray background `#f8f9fa` |
| 2 | **Header** | `d-flex justify-content-between align-items-center mb-3` | Title “Expenses”, **Add** button (icon + text) | Title: `h4 text-dark`; Add btn: `btn btn-primary` |
| 3 | **Filters Bar** | `row g-2 mb-4` | Three columns (sm‑6, md‑4) | `bg-white p-3 rounded shadow-sm` |
| 4 | **Date Range Picker** | `col` → `input-group` → `input` | Two inputs (start / end) with calendar icon (`bi-calendar`) | Border: `border-0`; bg: `#fff` |
| 5 | **Category Dropdown** | `col` → `select.form-select` | Options: All, Food, Travel, Utilities, etc. | Primary accent `#0d6efd` for focus |
| 6 | **Amount Slider** | `col` → `input[type=range].form-range` | Min 0 – Max 5000, live value display (`span`) | Slider thumb: `bg-primary` |
| 7 | **Clear Filters** | `col-auto` → `button.btn.btn-outline-secondary` | Resets all filter controls | Text: `#6c757d` |
| 8 | **Expense List Header** | `row fw-bold text-muted border-bottom pb-2 mb-2` | Columns: Date, Category, Description, Amount, Actions | Font size `sm` |
| 9 | **Expense Row** | `row align-items-center py-2 border-bottom` | Repeated via JS; each column uses `col-` classes (e.g., `col-2`, `col-3`) | Hover: `bg-hover-light` (`#e9ecef`) |
|10 | **Amount Chip** | `span.badge.bg-success.bg-opacity-10.text-success` | Shows formatted amount (`$12.34`) | Rounded pill, small padding |
|11 | **Action Buttons** | `button.btn.btn-sm.btn-outline-primary.me-1` (Edit) <br> `button.btn.btn-sm.btn-outline-danger` (Delete) | Inline icons (`bi-pencil`, `bi-trash`) | Focus ring `0` |
|12 | **Empty State** | `div.text-center py-5` | Message “No expenses match your filters.” + illustration | Muted text `text-muted` |
|13 | **Pagination** | `nav.mt-4` → `ul.pagination.justify-content-center` | Prev / Next + page numbers, responsive | Active page `page-item active > .page-link` |
|14 | **Responsive Breakpoints** | <ul><li>≥ md: 5‑column layout</li><li>sm: collapse description column</li><li>xs: stack filters vertically</li></ul> | Uses Bootstrap grid utilities | – |
|15 | **Accessibility** | All interactive elements have `aria-label`, focus outlines (`focus-visible`) | Keyboard‑navigable, screen‑reader friendly | – |
|16 | **Interaction Summary** | • Changing any filter triggers debounced API call (300 ms). <br> • “Clear Filters” resets UI & reloads full list. <br> • Edit opens modal (`modal.fade`) pre‑filled; Delete shows confirm toast. | – | – |
|17 | **Mockup File** | `mockups/design_expense_list_filters.html` (open in browser for interactive prototype) | – | – |

**Key Colors**  
- Primary: `#0d6efd` (Bootstrap default)  
- Success (amount): `#198754`  
- Backgrounds: `#f8f9fa` (page), `#fff` (cards)  
- Text: `#212529` (dark), `#6c757d` (muted)

**Notes**  
- All components rely on Bootstrap 5 utilities; no custom CSS beyond color overrides.  
- Icons use Bootstrap Icons (`bi-*`).  
- Ensure mobile‑first design; filters collapse into a single column on < 576 px.  