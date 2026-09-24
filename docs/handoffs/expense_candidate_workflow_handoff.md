# Handoff: Expense Candidate Workflow — remaining implementation

You are implementing the remaining gaps of an already-existing Expense Candidate workflow in this Rails app.
Most of the feature exists. **Do NOT rewrite what already works.** Implement only what is listed here.

- **Project stack:** Ruby on Rails 8, PostgreSQL, Minitest (`bin/rails test`), Bootstrap 5 ERB views, i18n via inline `t(key, default: "...")` (Spanish defaults, no locale-file edits).
- **Before finishing:** full suite green (`bin/rails test`), RuboCop clean on touched files, and run `graphify update .` at the very end (project knowledge-graph hook, no API cost).
- **Test style:** Minitest, Rails 8 assertions (`assert_equal`, `assert_not`, `assert_difference`). Follow the patterns already present in `test/models/expense_candidate_test.rb`, `test/services/expense_resolver/`, `test/services/expenses/processor_test.rb`.

---

## 1. Ground rules (must govern every decision)

1. Required Expense fields — the ONLY blockers — are: **amount, date, description, category, money_source**.
2. `ready` is an internal condition, never a dashboard tab. The Pending queue contains ONLY `needs_review` candidates.
3. Status derives ONLY from missing required fields. Confidence is diagnostic information, never a lifecycle gate.
4. Never invent a money source. Detection is deterministic (`MoneySources::Detector`), NOT AI. Do not add money_source to the AI prompt schema.
5. Never infer an expense category from the recipient or transfer mechanism ("Le transferí 50 mil a Juan" must not become a category).
6. Preserve the AI's category suggestion when it names a category that does not exist; preserve nil when the purpose is honestly undetermined.
7. If a candidate has all required info, `confirm!` converts it to an Expense without further user interaction. Future email/WhatsApp channels will call `confirm!` automatically on ready candidates — keep that path clean.
8. The Playground NEVER creates Expenses automatically, even for ready candidates. Only explicit user actions (`create`, `batch_create`, `confirm`) create Expenses.
9. Reuse existing concepts — one Expense model, one category system, one money-source system, the four existing statuses (`needs_review / ready / confirmed / discarded`).

---

## 2. Current architecture facts (verified — do not re-derive)

### Models
- `app/models/expense_candidate.rb` — `ExpenseCandidate`:
  - Statuses `%w[needs_review ready confirmed discarded]` (line ~16).
  - Transient attrs (line ~22): `currency, merchant, category_name, money_source_name, classification_source, suggested_category_id, suggested_category_name, duplicate, warnings, money_source_source`. These are `attr_accessor`s — NOT persisted columns. `suggested_category_name` currently survives only inside `metadata` for pipeline debug; **this is the gap task 2 fixes**.
  - `missing_fields` (jsonb, line ~120) currently: amount, date, category_id, money_source_id — **description is missing (task 1)**.
  - `checks` (line ~105): amount, currency, category (passes on `category_id || category_name`), valid date — **money_source and description missing (task 1)**.
  - `scope :pending` (line ~37): `where(status: %w[needs_review ready])` — **BUG vs spec: includes ready (task 1)**.
  - `confirm!` (line ~145) creates the Expense via `Expense.create!` directly — **bypasses `Expenses::Create` (task 1)**. It is already idempotent-ish (`return if confirmed? && expense_id.present?`) and wrapped in a transaction.
  - `discard!` sets `discarded_at`. Working; leave as is.
  - `create_expense_from_candidate!` (private, line ~204) hardcodes `source: "ai"` and truncates description.
  - Callbacks: `before_validation :set_defaults`, `after_validation :set_initial_status on: :create` (computes ready vs needs_review from `missing_fields.empty?`), `after_save :sync_missing_fields, if: :saved_change_to_category_id?`.
- `app/models/expense.rb` — `Expense < Transaction`; `Transaction` (app/models/transaction.rb) has `self.inheritance_column = :_type_disabled`; expense rows have NEGATIVE amounts (`normalize_signed_amount` negates for `kind == "expense"`); validations require amount (non-zero), date, kind, source; `before_validation on: :create` runs `TransactionRules::Applicator` (rules fill gaps; for `source == "ai"` rules prefer their category unless `category_locked_by_user`); `after_commit` fires `SpendingAlertService`.
- `app/services/expenses/create.rb` — `Expenses::Create.call(...)` is the SINGLE expense-creation entry point: parses/validates amount (cap 99,999,999.99), `occurred_at` defaults to today, resolves category via `Categories::ClosestResolver` (folds near-duplicate names, creates the Category if genuinely new), raises `Expenses::Create::Invalid`. **Always go through it.**

### Pipeline (text path, also used by image/audio via delegation)
```
Expenses::Processor.call(user:, input:, recording:, source:)
  → Expenses::Processors::Text (Base) → ExpenseResolver::Service
    → HeuristicResolver or Ai::Router (task :conversation_expense_parsing)
    → per expense entry: ExpenseResolver::CandidateDetector.call
        (Categories::Decision for category, MoneySourceResult via MoneySources::Detector,
         apply_matching_rule_category folds transaction-rule categories and nils the suggestion)
  → back in Processor#persist_candidate: ExpenseCandidate.create! per candidate (transient attrs copied for in-memory pipeline consumers)
```
- One input → one candidate per parsed expense (multi-expense already works).
- `Categories::Decision.call(user:, name:, activity:, category_id:)` returns `Result(category:, category_name:, suggested_category_name:, warnings:)` — the central category decision. A name that doesn't resolve becomes `category_name` + `suggested_category_name` (suggestion preserved). Kept honest for transfers: `ConversationExpenseParsing` prompt already forbids recipient-based inference.
- `MoneySources::Detector.call(user:, text:)` — scans names/bank/keyword identifiers, accent-normalized. Deterministic. KEEP AS IS.
- `Ai::Tasks::ConversationExpenseParsing` (app/services/ai/tasks/conversation_expense_parsing.rb): prompt outputs `{"expenses":[{original_text, amount, date, description, category}]}`; scores via `Expenses::ConfidenceCalculator`.
- `Ai::Tasks::ParsedExpense` (app/services/ai/tasks/parsed_expense.rb): `ATTRIBUTES = %i[original_text amount date description category money_source_hint confidence merchant currency money_source_id money_source_name]` — **`category_suggestion` missing (task 3)**. `build_expense` filters entries to ATTRIBUTES.
- `Expenses::Processor#persist_candidate` (app/services/expenses/processor.rb, line ~73): persists candidate; metadata currently stores engine/classification_source/category_name/money_source_name/warnings but NOT the suggestion; the transient `suggested_category_name` is copied onto the persisted instance in memory only, so it is LOST on reload (task 2 fixes).

### Controllers / views
- `ExpensePlaygroundController` (app/controllers/expense_playground_controller.rb):
  - `run` persists candidates only (never Expenses). `create` (line ~158) and `batch_create` are explicit confirm endpoints routing through `Expenses::Create`.
  - `resolve_mapping_category!` (line ~198) shows the fold-or-create category pattern via `Categories::ClosestResolver.call(user:, name:)` → `.category || Category.create!(...)`. Reuse this pattern.
- `ExpenseCandidatesController` (app/controllers/expense_candidates_controller.rb): `index` (default `@status = "needs_review"`), `show`, `update` (calls `recalculate_missing_fields!` + `recalculate_status!`), `confirm`, `discard`, `bulk_update`, `bulk_confirm`. `candidate_params` allows amount/date/description/category_id/money_source_id/original_input/original_text/confidence.
- Routes (config/routes.rb ~line 25): `resources :expense_candidates, only: [:index, :show, :update]` + member `post :confirm`, `post :discard` + collection `patch :bulk_update`, `post :bulk_confirm`.
- Dashboard (app/controllers/dashboard_controller.rb:11 and :20): `@pending_candidates = current_user.expense_candidates.pending.includes(:category, :money_source).limit(10)` — rendered in app/views/dashboard/index.html.erb (section at top with "Expense Candidates" header, table rows, `Review` button per row).
- Candidates index (app/views/expense_candidates/index.html.erb): tabs needs_review / **ready** / **confirmed** / discarded / all (ready/confirmed/all violate the exception-queue spec — task 5); bulk bar + `bulkConfirmModal` with `data-testid` attributes: `bulk-bar`, `bulk-category`, `bulk-source`, `bulk-confirm`, `candidates-table`, `candidate-row`; selects `#bulkCategorySelect`, `#bulkSourceSelect`; JS in inline `<script>`. **Preserve these testids and behaviors.**
- Candidates show (app/views/expense_candidates/show.html.erb): edit form (`form_with model: @candidate`) with amount / date / description / category_id (`collection_select`) / money_source_id; sidebar: confidence card, missing-fields card, actions card (`button_to confirm_expense_candidate_path`, `button_to discard_expense_candidate_path`), metadata card. **No suggestion UI today (task 5).**
- Helper `status_badge(status)` + `CANDIDATE_STATUS_CLASSES` / `CANDIDATE_STATUS_LABELS` (app/helpers/application_helper.rb:63-81). Also `category_badge`, `source_icon`, `field_class`, `field_error`, `money_field_value`.

### Conventions
- i18n: `t("expense_candidates.xxx", default: "Spanish text")` — follow exactly.
- Tests are Minitest; single file: `bin/rails test test/models/expense_candidate_test.rb`.
- Comments: only when non-obvious (see ruby-standards skill). No comments restating code.
- Controllers thin; `params.expect`; `rescue` only what has a plan.

---

## 2. Tasks

### TASK 1 — Model: pending scope, required fields, confirm! rewrite
Files: `app/models/expense_candidate.rb`, `test/models/expense_candidate_test.rb` (+ fix any tests broken by the scope/fields change).

**TDD first** — add/adjust Minitest in `test/models/expense_candidate_test.rb`:
- `.pending` returns ONLY `needs_review` records. Build one `needs_review` and one `ready` candidate (ready = amount/date/description/category_id/money_source_id all present); assert pending excludes ready.
- `missing_fields` returns `[]` when all 5 present (amount, date, description, category_id, money_source_id) and includes each key when nil/blank. `"description"` counts when nil or blank string.
- `checks` includes entries for: Amount, Date, Description, Category, Money source. Money source passes when `money_source_id` present OR `money_source_name` present (transient). Keep the existing Currency entry (diagnostic).
- `confirm!` creates the Expense via `Expenses::Create` semantics: Expense exists with candidate's amount/date/category/money_source, `source` preserved (`"text"` in test), candidate `status: "confirmed"`, `expense_id` set, `category_suggestion` nil.
- `confirm!` twice → exactly ONE Expense.
- `confirm!` with amount/date missing raises `ActiveRecord::RecordInvalid`; no Expense; status unchanged.
- `confirm!` on a `discarded` candidate raises `ActiveRecord::RecordInvalid` (do not resurrect).
- `confirm!` with `category_id: nil, category_suggestion: "Mascotas"` (no existing category) creates Category "Mascotas" (capitalized) for the user and uses it; if an existing user category has the same name, it is reused (that fold is `Expenses::Create`'s `resolve_category!` via `Categories::ClosestResolver` — you pass the name, it handles it).

**Model changes** (`expense_candidate.rb`):
1. `scope :pending, -> { needs_review }`
2. Update `missing_fields`:
   ```ruby
   def missing_fields
     fields = []
     fields << "amount" if amount.nil?
     fields << "date" if date.nil?
     fields << "description" if description.blank?
     fields << "category_id" if category_id.nil?
     fields << "money_source_id" if money_source_id.nil?
     fields
   end
   ```
   `set_initial_status` / `recalculate_status!` already key off `missing_fields.empty?` so ready now also requires description — intended. **Existing tests building candidates without description that expect `ready` must be updated to include description** (update fixtures, don't delete coverage).
3. `after_save :sync_missing_fields` — also trigger on `:money_source_id` and `:category_suggestion` changes:
   ```ruby
   after_save :sync_missing_fields, if: -> { saved_changes.keys & %w[category_id money_source_id category_suggestion] != [] }
   ```
4. Rewrite `confirm!`:
   ```ruby
   def confirm!
     raise ActiveRecord::RecordInvalid, "candidate is discarded" if discarded?
     return self if confirmed? && expense_id.present?

     ActiveRecord::Base.transaction do
       expense = create_expense_from_candidate!
       update!(status: "confirmed", expense_id: expense.id, confirmed_at: Time.current,
               category_id: expense.category_id, category_suggestion: nil)
     end
   end
   ```
5. Rewrite `create_expense_from_candidate!` (private) to use `Expenses::Create`:
   ```ruby
   def create_expense_from_candidate!
     raise ActiveRecord::RecordInvalid, self if amount.nil? || date.nil?

     Expenses::Create.call(
       user: user,
       amount: amount.abs,
       description: description.presence || merchant.presence || category_name.presence || "Gasto sin descripción",
       category: resolve_category,
       occurred_at: date,
       source: source.presence || "ai",
       money_source: money_source
     )
   end

   def resolve_category
     return category if category.present?
     return category_name.presence if category_name.present?

     category_suggestion.presence
   end
   ```
   Do NOT resolve names yourself — pass id or name to `Expenses::Create` (its `resolve_category!` folds near-duplicates via `Categories::ClosestResolver` and creates genuinely-new categories). Let `Expenses::Create::Invalid` surface; controllers already rescue it (playground) — add a matching rescue in `ExpenseCandidatesController#confirm` (see task 5) or let `ActiveRecord::RecordInvalid` be raised by the model (`confirm!` callers rescue it; wrap `Expenses::Create::Invalid` as `raise ActiveRecord::RecordInvalid, e.message` inside the transaction for a single error surface).
   Note: the suggestion-only path works because `Expenses::Create` treats a category NAME exactly like `Categories::ClosestResolver` + create (playground does the same with `candidate_category`). Do not duplicate that logic in the model.
6. `discard!` stays. `recalculate_status!`/`recalculate_missing_fields!` stay.

**Controller:** `ExpenseCandidatesController#confirm` keeps the `missing_fields.empty?` pre-check; extend the rescue:
```ruby
rescue [ ActiveRecord::RecordInvalid, Expenses::Create::Invalid ] => e
  redirect_to expense_candidate_path(@candidate), alert: e.message
```

**Run:** `bin/rails test test/models/expense_candidate_test.rb test/controllers test/integration` and fix regressions (tests asserting `pending` includes ready WILL need updating — update, don't delete).

### TASK 2 — Migration: persisted `category_suggestion` (no backfill)
1. TDD first: model tests — `category_suggestion` persists; `suggested_category_name` alias returns it; `from_h` accepts `category_suggestion`.
2. Migration `db/migrate/<timestamp>_add_category_suggestion_to_expense_candidates.rb` (match the latest `[8.x]` version used in existing migrations):
   ```ruby
   class AddCategorySuggestionToExpenseCandidates < ActiveRecord::Migration[8.0]
     def change
       add_column :expense_candidates, :category_suggestion, :string
     end
   end
   ```
   Then `bin/rails db:migrate`.
3. Model wiring:
   - Remove `suggested_category_name` from the `attr_accessor` list and replace with:
     ```ruby
     def suggested_category_name
       category_suggestion
     end
     ```
     (read alias only — canonical storage is `category_suggestion`). Keep `suggested_category_id` transient as-is.
   - `from_h`: accept `category_suggestion:` like the other fields.
4. `Expenses::Processor#persist_candidate`: persist the suggestion:
   ```ruby
   persisted = ExpenseCandidate.create!(
     ..., category_suggestion: candidate.suggested_category_name.presence, ...
   )
   ```
   (add to the create! call; keep the in-memory transient copies below).
5. `ExpenseResolver::CandidateDetector` (task 3 wires the AI value here — the persisted candidate is built from `category_result.suggested_category_name` today; after tasks 2+3 the persisted column carries it; `apply_matching_rule_category` must also nil the suggestion when a rule matched:
   ```ruby
   candidate.category_suggestion = nil
   ```
   in addition to `candidate.suggested_category_name = nil`).
6. **No backfill migration.** Pre-existing candidates keep `category_suggestion: nil` and stay `needs_review` — manual review handles them.

### TASK 3 — AI parsing schema: `category_suggestion`
Files: `app/services/ai/tasks/conversation_expense_parsing.rb`, `app/services/ai/tasks/parsed_expense.rb`, `app/services/expense_resolver/candidate_detector.rb`, plus tests (find the conversation parsing test under `test/services/ai/` or create it).

**Do NOT add money_source to the AI schema** — money source stays deterministic via `MoneySources::Detector` scanning the raw text.

**TDD first** (unit tests with canned AI entries, following existing stubbing patterns — never assert live AI output):
- Entry `{"category": null, "category_suggestion": "Mascotas", ...}` → parsed entry carries `category_suggestion == "Mascotas"`, `category == nil`.
- Entry `{"category": "Comida y restaurantes", "category_suggestion": "Mascotas", ...}` (both returned) → existing resolved category wins; candidate `category_id` set; suggestion NOT surfaced (clear it — suggestion is only meaningful when `category` itself was unresolved).
- Entry both null → candidate `category_suggestion: nil`, `needs_review` (missing fields).

**Prompt changes** (`system_prompt`):
- Output object per expense gains `"category_suggestion"`. Rules to add:
  - `category_suggestion`: "When you believe the expense belongs to a category that is NOT in Available categories, return category: null and put that name here. If the purpose of the expense cannot be determined from the message, return null for both category and category_suggestion. Do not infer the purpose from the recipient or the transfer mechanism."
- Keep ALL existing anti-inference rules verbatim (transfers to persons must not imply category).

**Code changes:**
- `ParsedExpense::ATTRIBUTES` — add `category_suggestion` (nothing else). `build_expense` passes it through automatically.
- `CandidateDetector#call` initializer: build the suggestion from Decision first, AI second:
  ```ruby
  suggested = category_result.suggested_category_name.presence ||
              expense.respond_to?(:category_suggestion) ? expense.category_suggestion : nil
  ```
  (write it cleanly with guards, not nested ternaries). When Decision already resolved a real category, ensure the AI's suggestion is dropped (Decision path covers it; enforce in the initializer assignment order).
- When `apply_matching_rule_category` folds a rule category, nil the suggestion (persisted column, see task 2).

### TASK 4 — Playground shows Ready for evaluation (verify + wire; no auto-create)
Files: `app/services/expense_resolver/serializer.rb`, `app/controllers/expense_playground_controller.rb`, `app/services/expenses/processor.rb`.

- `persist_candidate` (processor): add `category_suggestion:` to the `ExpenseCandidate.create!` call (task 2). An unresolved suggestion must NOT count as a category — status stays `needs_review` because `category_id` is nil. Already true via `missing_fields` — verify with a test.
- Serializer: expose `status` and `category_suggestion` in the candidate JSON the playground front-end receives (find the merge hash in `app/services/expense_resolver/serializer.rb`; add `"status" => candidate.status, "category_suggestion" => candidate.category_suggestion`). The playground shows the status for evaluation (e.g. "Status: Ready") — surface it next to the existing summary values in `app/views/expense_playground/show.html.erb` (the `pg-sum-*` area around lines 1189-1198); do NOT redesign the playground UI.
- **Do NOT auto-create expenses from playground** — already true; add one integration test asserting `POST /expense-playground/run` with a fully-parseable input creates an `ExpenseCandidate` with `status == "ready"` and zero new `Expense` rows.

### TASK 4 — Exception-queue views + suggestion UX
Files: `app/views/expense_candidates/index.html.erb`, `app/views/expense_candidates/show.html.erb`, `app/views/dashboard/index.html.erb`, `ExpenseCandidatesController`, routes, tests.

1. **Index tabs** — replace the current five tabs with two:
   - **Pending** → `expense_candidates_path` (default), label "Pendientes", badge `current_user.expense_candidates.needs_review.count`.
   - **Discarded** → `expense_candidates_path(status: "discarded")`.
   Controller: `@status = params[:status].presence || "needs_review"` and only allow `%w[needs_review discarded]` (any other value falls back to default). Remove Ready/Confirmed/All tabs. Keep the bulk bar + `bulkConfirmModal` (bulk confirm is a batched user action on Pending rows) — testids unchanged.
2. **Index rows:** where category is missing, if `candidate.category_suggestion.present?` show a warning badge `Sugerida: "<name>"` instead of plain "Faltante"; otherwise keep current "Faltante". Money source cell unchanged.
3. **Show page** — inside the Category form-group, before the `collection_select`:
   - If `@candidate.category_id.nil? && @candidate.category_suggestion.present?`:
     ```erb
     <div class="alert alert-info py-2">
       <i class="bi bi-lightbulb me-1"></i>
       <strong>Sugerida por IA:</strong> <%= @candidate.category_suggestion %>
       <%= button_to t("expense_candidates.create_suggested", default: 'Crear "%s"' % @candidate.category_suggestion),
                     accept_suggestion_expense_candidate_path(@candidate),
                     method: :post, class: "btn btn-sm btn-outline-primary ms-2" %>
       <small class="d-block text-muted mt-1"><%= t("expense_candidates.suggestion_hint", default: "o elige una categoría existente abajo.") %></small>
     </div>
     ```
   - The select stays so the user can pick an existing category instead (choosing one via the normal update flow clears nothing automatically — the suggestion is cleared on accept/confirm only, per task 1's `confirm!` update and `accept_suggestion`).
4. **New member action** in `ExpenseCandidatesController`:
   ```ruby
   # POST /expense_candidates/:id/accept_suggestion
   def accept_suggestion
     name = @candidate.category_suggestion.to_s.strip
     if name.blank?
       redirect_to expense_candidate_path(@candidate),
                   alert: t("expense_candidates.no_suggestion", default: "No hay sugerencia de categoría.")
       return
     end

     resolved = Categories::ClosestResolver.call(user: current_user, name: name)
     category = resolved.category ||
                Category.create!(name: name.split.map(&:capitalize).join(" "), user: current_user, is_default: false)
     @candidate.update!(category_id: category.id, category_suggestion: nil)
     @candidate.recalculate_missing_fields!
     @candidate.recalculate_status!

     redirect_to expense_candidate_path(@candidate),
                 notice: t("expense_candidates.suggestion_accepted",
                           default: "Categoría \"#{category.name}\" asignada.")
   rescue ActiveRecord::RecordInvalid => e
     redirect_to expense_candidate_path(@candidate), alert: e.message
   end
   ```
   Route: add `post :accept_suggestion` inside the member block of `resources :expense_candidates`. Pattern copied from `ExpensePlaygroundController#resolve_mapping_category!` (lines ~198-217) so "very close" names fold into existing categories and only genuinely-new names create one.
   **Do NOT permit `category_suggestion` in `candidate_params`** — the suggestion is cleared only by accept/confirm flows.
5. **Dashboard:** after task 1 the existing `@pending_candidates = ... .pending` shows needs_review only — no view change needed; verify with a dashboard controller test. The section already shows the "Expense Candidates" card with Review buttons.
6. i18n: inline `t(..., default: "Spanish")` only.

### TASK 5 — ConfidenceCalculator (verify-only)
`Expenses::ConfidenceCalculator` already awards **0.0** for an unsupported category (app/services/expenses/confidence_calculator.rb, `category_signal`) and status never uses confidence. Expected change: none. Add/keep one test proving: score for an entry with a category name NOT in the list equals the score with category nil (unsupported earns nothing). Skip if `test/services/expenses/confidence_calculator_test.rb` already covers it.

### TASK 6 — Explicit do-NOT list
- No workflow engine, event sourcing, approval framework.
- No new statuses (keep the four), no second Expense/Category/MoneySource model.
- No Email/WhatsApp automation. Future channels = create candidate, call `confirm!` when ready. Nothing to build now.
- No changes to `MoneySources::Detector`, `ExpenseResolver::Service` engine routing, AI tiering/cost.
- Do not redesign playground JS; all `data-testid`s and `bulkConfirmModal` behavior must keep working.
- Do not add `category_suggestion` to `candidate_params`; do not add money_source to the AI prompt.

---

## 3. Full acceptance criteria (must all hold after implementation)

### Complete extraction

Input:

> "Ayer compré mercado en Éxito por 85 mil y pagué con Davibank."

Result:

```text
Candidate
amount: 85000
date: yesterday
description: mercado en Éxito
category: Comida y restaurantes
money_source: Davibank
```

Candidate is ready.

In Playground:

* Candidate is created.
* Final Expense is NOT automatically created.

In future automated channels:

* Candidate can automatically become an Expense.

### Missing money source

Input:

> "Gasté 50 mil en gasolina."

Result:

```text
amount: 50000
category: Transporte
money_source: nil
```

Candidate:

```text
needs_review
```

It appears under Pending.

### Unknown category with suggestion

Input:

> "Compré comida para mi perro por 80 mil en Laika y pagué con Davibank."

If `Mascotas` does not exist:

```text
category: nil
category_suggestion: Mascotas
money_source: Davibank
```

Candidate:

```text
needs_review
```

The user can accept/create `Mascotas` or choose an existing category.

### Ambiguous transfer

Input:

> "Le transferí 50 mil a Juan."

Result should not invent a category.

Possible result:

```text
amount: 50000
category: nil
category_suggestion: nil
money_source: nil
```

Candidate:

```text
needs_review
```

### Pending approval

A Pending Candidate is edited until all required information is valid.

User clicks Approve/Create Expense.

Result:

```text
Candidate → Expense
```

The Candidate no longer appears under Pending.

### Discard

User clicks Discard.

Result:

```text
Candidate → Discarded
```

It disappears from Pending and appears under Discarded.

No Expense is created.

### Ready candidates

Ready Candidates must NOT appear in the Pending dashboard queue.

They are automatically convertible into Expenses in the automated production workflow.

The Playground may display their ready status for evaluation, but must not create the Expense automatically.

### Multiple expenses

Each expense extracted from one input becomes an independent Candidate.

Each Candidate independently determines whether it is ready or needs review.

Example:

> "Compré mercado por 180 mil en Éxito y después gasté 50 mil en gasolina."

Should produce two independent Candidates. If one is missing its money source, only that one requires review — the other is ready.

### Final principle (must govern all decisions)

> **If the system has enough information to create a valid Expense, don't ask the user. If it doesn't, create a Candidate in Pending and ask only for what is missing or unresolved.**

The Playground is for evaluating Candidates.

The production ingestion channels will eventually use the same Candidate layer to automate ready expenses and send only exceptions to the user.

### 3.1 Regression checklist (how to verify each criterion)

| # | Criterion | How to verify |
|---|-----------|---------------|
| 1 | Complete extraction → ready, no Expense | Integration test on `POST /expense-playground/run`; assert candidate `status == "ready"` and `Expense.count` unchanged; JSON shows `status: "ready"` |
| 2 | Missing money source → needs_review, in Pending | Seed Transporte category; text with no source name; assert candidate in `needs_review`; assert `ExpenseCandidatesController#index` (default) and Dashboard render it |
| 3 | Unknown category with suggestion | Assert persisted `category_suggestion == "Mascotas"`; request test: `POST /expense_candidates/:id/accept_suggestion` creates the Category, clears suggestion, recalculates to ready |
| 4 | Ambiguous transfer | Integration test; assert `category_id.nil? && category_suggestion.nil?` |
| 5 | Approve flow | Controller test: update all 5 fields → `post :confirm` → Expense exists, candidate `confirmed`, absent from Pending |
| 6 | Discard flow | Controller test: `post :discard` → `discarded`, `discarded_at` set, no Expense, listed only under Discarded tab |
| 7 | Ready candidates not in Pending | Model test on `.pending` scope + dashboard controller test |
| 8 | Multiple expenses | Pipeline test: one input → 2 candidates, independently classified |
| 9 | Double confirm idempotency | Model test: `confirm!` twice → exactly one Expense |
| 10 | Full suite | `bin/rails test` all green; `rubocop` clean on touched files |

**Testing note for criteria 1–4:** they depend on AI behavior. Do NOT assert live AI output. Unit-test `ParsedExpense.build_expense` / the prompt schema with canned entries, and integration-test the pipeline by stubbing `Ai::Router` (or whatever stubbing pattern existing tests in `test/services/expense_resolver/` and `test/services/expenses/processor_test.rb` use).

---

## 4. Commit order

1. Task 1 — model scope/fields/`confirm!` + tests
2. Task 2 — migration + persistence wiring + tests
3. Task 3 — AI schema + `CandidateDetector` wiring + tests
4. Task 4 — playground serializer/eval exposure + integration test
5. Task 4 (views) + `accept_suggestion` action + tests
6. Final: full `bin/rails test`, RuboCop on touched files, then `graphify update .`
