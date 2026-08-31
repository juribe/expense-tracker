# Design Spec — Hybrid Financial Setup Wizard

Onboarding wizard that lets users configure Accounts, Credit Cards, and Loans
through either **manual entry**, **file import**, or **skip** — the choice is
made independently per financial source type. Built on the existing
`MoneySource` / `CreditAccount` / `Transaction` models; no new UI frameworks.

## 1. Scope & Principles

- One reusable wizard flow (`FinancialSetupWizard`) hosting one step per
  financial source type plus a final Review step. Future source types
  (e.g. wallets, cash) plug in without a redesign.
- The manual/import/skip decision is part of each step's state, not a global setting.
- Import is a **separate pipeline** from the wizard UI. The AI extraction layer
  returns structured, validated data; it never writes ActiveRecord records directly.
- **No record is created from an extraction without explicit user confirmation.**
- Documents and passwords are handled securely (see Security below).

## 2. Screens & Flow Map

```
[Entry] -> [Accounts] -> [Credit Cards] -> [Loans] -> [Review] -> [Done]
              | per step: Manual | Import | Skip
```

Each source-type step offers three top-level options (Manual / Import / Skip).
Only the Review step is mandatory; all source steps can be skipped.

## 3. Step Navigation (progress stepper)

- **Component:** horizontal stepper rendered above the step content.
  `d-flex flex-wrap align-items-center gap-2`, hidden on small screens in favor
  of a "Step X of 4" label.
- Each step: `badge` circle (number or check) + label. States:
  - **Done** → `bg-success`, `bi-check-lg`, label `text-muted`.
  - **Current** → `bg-primary`, bold label.
  - **Pending** → `bg-secondary`/`bg-light`, `text-muted`.
- **Global chrome bar** (sticky top of card): `d-flex justify-content-between`.
  Left = `Back` (`btn btn-outline-secondary`, `bi-arrow-left`, disabled on Entry).
  Right = `Continue` (`btn btn-primary`, `bi-arrow-right`), plus an
  "Exit & resume later" ghost link (`bi-box-arrow-right`) that persists progress.
- **Progress persistence:** every completed/edited step writes to a
  `financial_setup` session/DB record. Navigating back or leaving re-renders
  previously entered data (see §9).

## 4. Entry Screen

Centered, friendly intro card (no stepper yet).

- Icon `bi-magic` (or `bi-bank`) in a large rounded `bg-primary-subtle` circle.
- Title: **"Let's set up your finances"** (`h2`/`h3`, heading color).
- Body copy: "Add your accounts, credit cards, and loans so we can build your
  initial financial overview. You can enter the information manually or upload
  an existing statement."
- Primary CTA: `btn btn-primary btn-lg` **"Start setup"** (`bi-rocket-takeoff`).
- Secondary: `btn btn-link text-muted` **"Not now"** → exits to dashboard,
  no data lost, prompt to resume later (resume banner shown on next visit).
- Include a small row of three feature chips (Manual · Import · Skip anytime) for orientation.

## 5. Financial Source Selection Screen (per step)

Reusable component — identical structure for Accounts, Credit Cards, Loans.

- Step title (e.g. **"Accounts"**) + prompt **"How would you like to add your accounts?"**
- Three selectable cards in `row g-3`, each `col-12 col-md-4`:
  1. **Add manually** — `bi-pencil-square`, subtitle "Add one or more by entering the information yourself."
  2. **Import a statement** — `bi-upload`, subtitle "Upload a PDF, CSV, or Excel file and extract the information automatically."
  3. **Skip for now** — `bi-arrow-right-circle`, subtitle "Continue without adding accounts."
- Cards are radio-style: `card border shadow-sm` with `.selected` state adding
  `border-primary` + `bg-primary-subtle` ring. Selecting auto-advances to the
  corresponding sub-screen on "Continue".
- Icons/colors follow `source_kind_icon` mapping (account→`bi-bank`,
  credit_card→`bi-credit-card-2-front`, loan→`bi-cash-coin`).

## 6. Manual Entry Sub-screen

Reusable multi-row form allowing 1..n sources without leaving the wizard.

- List of entry cards, each a `card mb-3` with a header row:
  `Name` (bold) + `btn-group btn-group-sm` (edit `bi-pencil`,
  remove `bi-trash`, both outline).
- **"+ Add another"** button below: `btn btn-outline-primary` `bi-plus-lg`.
- Fields (reuse existing `_form.html.erb` field groups / helpers):
  - **Account:** Name, Bank, Starting balance (`$` input-group, money input).
  - **Credit Card:** Name, Issuer/Bank, Card brand, Last four digits,
    Credit limit, Interest rate + type. (Statement/payment day left optional —
    advanced info completed later.)
  - **Loan:** Name, Lender, Outstanding balance (via `credit_account`),
    Monthly payment (`installment_amount`), Interest rate + type,
    Payment date/frequency. (Principal, start/end dates optional.)
- Validation via existing `field_class` / `field_error` helpers and
  `money_field_value` prefills; invalid card shows `is-invalid` + message.
- Footer: Back / Continue. Continue validates the current row set before advancing.

## 7. File Upload Sub-screen

When user picks **Import a statement**.

- Step title **"Upload your statement"**; helper text: "Upload a recent bank,
  credit card, or loan statement. We'll extract the relevant information and
  let you review it before anything is added to your account."
- **Dropzone** card: `border border-2 border-dashed rounded p-5 text-center`
  (`bi-cloud-arrow-up display-4`). Accepts PDF / CSV / XLSX; drag & drop + file
  picker (hidden `input[type=file]`, `accept=".pdf,.csv,.xlsx"`).
- Shows selected file chip (`bi-file-earmark-*` + name + size).
- **States:**
  - **Idle** — dashed dropzone + "Browse files" link.
  - **Uploading** — spinner `spinner-border spinner-border-sm` + progress bar
    `progress` with animated width; label "Uploading…".
  - **Processing** — `bi-stars` + "Processing your statement…" + indeterminate
    progress (the pipeline runs in a background job).
  - **Error** — `alert alert-danger` with retry `btn btn-outline-danger` (`bi-arrow-clockwise`).
- After processing, the flow transitions to Extraction Review (§8).

## 8. Extraction Review & Duplicate Handling

Never persist records until user confirms.

- Title: **"We found N account(s)"** (or cards/loans). List of detected items,
  each a `card` with a `form-check`/`form-switch` "keep" toggle:
  - Line: `source_kind_icon` + **Name** + `badge bg-light text-dark` last-four
    (e.g. `Bancolombia ••••1234`), second line "Savings account", third line
    "Balance: $5,420,000" (`text-success`/`text-danger` by sign).
  - Actions per row: **Edit** (`bi-pencil`) opens inline fields; **Remove**
    (`bi-trash`, `btn-outline-danger`).
- **Transactions summary** (when present): `alert alert-info` line
  "86 transactions found · 75 automatically categorized · 11 need review"
  with a "Review transactions" link opening a review panel (list of date /
  description / amount / category badge with a select to override category).
- **Duplicate detection:** if an uploaded source matches an existing
  `MoneySource` (matched by institution + last-four/identifier), show the item
  with a `badge bg-warning text-dark` "Possible duplicate" and require a choice:
  **Update existing** (`btn btn-outline-primary`) / **Create new**
  (`btn btn-outline-secondary`) / **Ignore** (`btn btn-outline-danger`).
- Footer: **Cancel import** (outline), **Confirm & continue** (`btn btn-primary`).

## 9. Resume / Persistence

- Wizard state persisted per user after each step: step index, per-step choice
  (manual/import/skip), draft sources, import result (review state), extracted
  transactions.
- Re-entering the wizard resumes at the last incomplete step, restoring drafts.
- An "unfinished setup" banner appears on the dashboard/money-sources page when
  a partially-completed setup exists, offering **Resume** / **Dismiss**.

## 10. Final Review & Completion

- Title **"Your financial setup"**. Three summary rows with icons and counts:
  `bi-bank` **2 Accounts** · `bi-credit-card-2-front` **2 Credit Cards** ·
  `bi-cash-coin` **3 Loans** — each a `card`/`list-group-item` with
  `d-flex justify-content-between`.
- Divider, then bold total: **"7 financial sources configured"**
  (`fs-4 fw-bold`), plus total transactions count if imported.
- Each row expands (`collapse`) to the configured source names/balances.
- Footer: **Back** to edit (`btn btn-outline-secondary`), **Complete setup**
  (`btn btn-primary btn-lg`, `bi-check-circle`).
- **Done state:** success panel — `bi-emoji-sunglasses`/`bi-check-circle-fill`
  `text-success` + **"Your finances are ready"**; CTA **"Go to dashboard"**
  (`btn btn-primary`, `bi-grid-1x2`). Records created in a single transaction.

## 11. Security & Privacy

- **Never** persist or log document passwords; never put passwords in background
  job arguments. Passwords are held in memory only during decryption, then discarded.
- Password-protected PDF flow: detect → inline `card` "This document is
  password protected — Enter the password to continue." with password `input` +
  **Unlock document** button; wrong password → `alert alert-danger` retry.
- Uploaded documents stored via the app's existing authorization/attachment
  model; define a **retention policy** (auto-purge after import completes or
  within N days) and expose delete.
- Avoid logging sensitive document contents; avoid sending more than necessary
  to AI services. AI returns structured data validated before any DB write.

## 12. Responsive & Accessibility

- **Responsive:** stepper collapses to a compact "Step X of 4" label on
  `<lg`. Selection cards stack to `col-12`. Forms already use
  `col-md-6`/`col-12`. Dropzone and review cards span full width.
- **A11y:** stepper uses `aria-current="step"`; selection cards use
  radio semantics (`role="radio"`/`aria-checked`); toggles use real
  `form-check` inputs; invalid fields wired to `aria-describedby`; keyboard
  reachable (native buttons/inputs); color not the only status cue
  (icons + text accompany badges); focus moved to step heading on advance.

## 13. Empty / Loading / Error / Success Summary

| State | Component | Classes |
|---|---|---|
| Empty (step with nothing yet) | friendly prompt + the 3-choice cards | `card`, `text-muted` |
| Loading | spinner + indeterminate bar | `spinner-border`, `progress` |
| Error (upload/extract) | danger alert + retry | `alert alert-danger`, `btn-outline-danger` |
| Success (extraction) | info summary + confirm | `alert alert-info`, `btn-primary` |
| Duplicate | warning badge + 3-way choice | `badge bg-warning text-dark` |
| Completion | success hero + dashboard CTA | `text-success`, `btn-primary` |

## 14. Reusable Architecture (for the Developer)

- `FinancialSetupWizard` orchestrates ordered steps; each step defines a
  `kind`, label, icon, manual form fields, and import review type.
- `ImportPipeline` = upload → validation → type detection → password handling →
  text/table extraction → normalization → source extraction → transaction
  extraction → validation → review → create/update. Runs off the UI thread.
- New source types = add a step config + a manual form partial; no wizard
  rewrite.