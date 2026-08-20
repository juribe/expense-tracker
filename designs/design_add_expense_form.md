### Design Spec: Add Expense Form (Expense Tracker)

**Layout & Structure**
*   **Container:** Centered Modal (`modal-dialog-centered`) or Card (`card`) for focus.
*   **Grid:** Single column layout for mobile; 2-column grid (`row g-3`) for desktop.
*   **Spacing:** Standardized gutters (`g-3`) and vertical padding (`py-4`).

**Components (Bootstrap 5)**
*   **Header:** Title `h5` + Close icon (`btn-close`).
*   **Input - Amount:** `form-control` with `input-group` (prefix: `$`).
*   **Input - Description:** `form-control` (placeholder: "e.g., Grocery Store").
*   **Select - Category:** `form-select` (Options: Food, Transport, Bills, Entertainment, Misc).
*   **Input - Date:** `form-control` (`type="date"`).
*   **Action Buttons:** 
    *   Primary: `btn-primary` ("Save Expense")
    *   Secondary: `btn-outline-secondary` ("Cancel")

**Color Palette**
*   **Primary (Action):** `#0D6EFD` (Bootstrap Primary Blue).
*   **Success (Income/Add):** `#198754` (Bootstrap Green).
*   **Danger (Expense/Delete):** `#DC3545` (Bootstrap Red).
*   **Background:** `#F8F9FA` (Light Gray) for page; `#FFFFFF` for card.
*   **Text:** `#212529` (Dark) for labels; `#6C757D` (Muted) for hints.

**Interactions & UX**
*   **Focus States:** Blue glow on active inputs (`form-control:focus`).
*   **Validation:** 
    *   Red border (`is-invalid`) if amount is empty/zero on submit.
    *   Success toast/notification upon successful entry.
*   **Feedback:** Disable "Save" button (`disabled`) until required fields are filled.
*   **Keyboard:** `Enter` key triggers the primary "Save" action.