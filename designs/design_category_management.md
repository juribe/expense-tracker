**Category Management – UI/UX Spec (Bootstrap 5)**  

1. **Screen layout** – Full‑width card (`.card`) centered in `.container‑lg`; header (`.card-header`) contains title “Categories” and “Add Category” button (`.btn-primary`). Body (`.card-body`) holds a sortable list (`.list-group`) of groups.  

2. **Group header** – `.list-group-item .d-flex .justify-content-between .align-items-center`  
   * Group name (editable inline)  
   * “Add Category” icon (`.btn btn-sm btn-outline-success`)  
   * Drag handle (`.icon-grip-horizontal`) for re‑ordering groups via **SortableJS**.  

3. **Category row** – `.list-group-item .d-flex .align-items-center .gap-2`  
   * Leading icon avatar (`.rounded-circle bg-light`) – click opens **Icon Picker**.  
   * Category name (editable inline).  
   * “Edit” (`.btn btn-sm btn-outline-primary`) and “Delete” (`.btn btn-sm btn-outline-danger`) actions.  

4. **Icon Picker modal** – `.modal .modal-dialog .modal-content`  
   * Tabs: **Emoji**, **SVG library**, **Upload** (`.nav-tabs`).  
   * Search bar (`.form-control-sm`).  
   * Grid of selectable icons (`.row .col-2 .icon-selectable`) – click sets icon and closes modal.  

5. **Add / Edit Category modal** – same structure as picker, plus fields:  
   * Name (`.form-control`),  
   * Optional description,  
   * Dropdown to select existing group or **Create New Group** (`.form-select`).  

6. **Custom grouping** – Users can:  
   * Create a new group from the Add/Edit modal.  
   * Drag categories between groups.  
   * Re‑order groups via drag handle.  
   * List auto‑sorts alphabetically unless user toggles “Manual order” (`.form-check-input`).  

7. **Deletion workflow** – Click “Delete” → **Confirmation modal** (`.modal-danger`).  
   * Message: “Delete category ‘X’? All linked transactions will be moved to **[Select fallback category]** or **Archived**.”  
   * Dropdown of fallback categories (excluding the one being deleted).  
   * Options: **Reassign** or **Archive** (soft‑delete).  

8. **Data‑integrity rules** (backend contract, reflected in UI):  
   * On **Reassign**, all transactions update `category_id` → selected fallback.  
   * On **Archive**, category flag `archived = true`; transactions remain linked but category hidden from active list.  
   * Deleting a **group** follows same pattern: must choose a fallback group or archive it; all child categories inherit the chosen rule.  

9. **Colors & theming** – Primary `#0d6efd` (buttons, active group header), Secondary `#6c757d` (icons, dividers), Success `#198754` (add actions), Danger `#dc3545` (delete). Light background `#f8f9fa` for cards; dark mode swaps to `.bg-dark .text-light`.  

10. **Interactions & feedback**  
    * Inline edits save on **Enter** or blur, showing a brief `.toast` success.  
    * Drag‑and‑drop shows placeholder (`.bg-primary bg-opacity-25`).  
    * Icon selection highlights with `.border-primary`.  
    * All modals use `.fade` transition; focus trap enforced.  

*All typographical errors corrected; component names match Bootstrap 5 conventions.*