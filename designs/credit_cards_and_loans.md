# Credit Cards & Loans — UI/UX Design Specification

*(Bootstrap 5.3 + Bootstrap Icons, ERB views, Plus Jakarta Sans, app design tokens)*

Scope: make `credit_card` a distinct credit/debt source and introduce `loan` as a new
`MoneySource` kind, with credit/debt-specific data kept out of `MoneySource` and rendered
through kind-specific UI. Mockup: `mockups/credit_cards_and_loans.html`.

## 1. Domain surface the UI relies on

UI must never duplicate credit/debt math. Views call helpers/model methods; the backend is
the source of truth.

| Method / helper | Where | Output used by UI |
|---|---|---|
| `source.credit_card?`, `source.loan?` | MoneySource predicate (`loan?` new) | Chooses card variant & panel |
| `source.debt?` | `credit_card? \|\| loan?` | Groups the index, debt styling |
| `source.credit_account?` / `credit_account` | `has_one :credit_account` | Access to credit/debt fields |
| `used_credit`, `available_credit`, `credit_limit`, `credit_utilization` | MoneySource via CreditAccount | Card "Credit available", progress bar |
| `interest_rate_label` | Helper → `"24.5% EA"` | Rate badge/text |
| `statement_day`, `payment_due_day` | CreditAccount | Billing cycle display |
| `outstanding_balance`, `principal_amount`, `installment_amount` | MoneySource via CreditAccount (loan) | Loan card/detail |
| `installment_count`, `remaining_installments`, `payment_frequency` | CreditAccount (loan) | Loan detail |
| `repayment_progress` | MoneySource (loan) | "42% repaid" progress bar |
| `balance_label` | Existing | Keeps sign/currency formatting consistent |
| `source_kind_icon`, `source_kind_label`, `source_kind_options` | ApplicationHelper | Add `loan` → icon `cash-coin`, label "Loan" |
| `credit_utilization_class(pct)` | ApplicationHelper (new) | Progress bar color (see §5) |
| `field_class`, `field_error`, `money_field_value` | Existing helpers | Form validation + money inputs |

**Sign convention (single source of truth).** Assets (`account`, `debit_card` via parent,
`cash`, `wallet`) keep today's behavior: positive balance = money owned, `text-success`.
Debt sources (credit card, loan) expose the **positive magnitude** of what is owed
(`used_credit` / `outstanding_balance`); `balance` returns its **negative** so the existing
debt-means-negative rendering stays consistent. Only viewing code decides whether to render
a signed `-$` or a labelled magnitude ($ + "Used"/"Outstanding"); the amount values and sign
are never recomputed in views/controllers/React.

## 2. Money Sources index

Existing patterns preserved (`row g-3`, `col-12 col-md-6 col-lg-4`, `card h-100 shadow-sm`).
New: two grouped sections instead of one flat grid.

### 2.1 Grouping
- **"Assets & Money"** — `account`, `debit_card`, `cash`, `wallet`. Rendered when any exist.
- **"Credit & Debt"** — `credit_card`, `loan`. Rendered when any exist (hidden entirely if
  none — never show an empty section header).
- Section title: `h6 fw-bold text-uppercase`; debt one uses `.text-danger`
  (mockup uses `.debt-section-title`) plus a one-line muted caption "Credit cards and loans
  are debt. The amounts below are what you owe…".
- Empty state (no sources at all): current `card shadow-sm` + `p-5 text-center` block,
  unchanged.

### 2.2 Card variants

| Variant | Classes | Content |
|---|---|---|
| Asset (unchanged) | `card h-100 shadow-sm` | Icon + name, kind label, bank, balance (`text-success`), tags, tx count, actions |
| Debit card (unchanged) | as above | `→ {parent.name}` + "Linked card / balance on parent" |
| Credit card (new) | `card card-debt h-100 shadow-sm` | See 2.3 |
| Loan (new) | `card card-debt h-100 shadow-sm` | See 2.4 |

`.card-debt` = left accent `border-left: 4px solid var(--bs-danger)` (one global rule added
to the layout `<style>` block; overrides the app's `.card { border: none }`).

Actions: existing `btn-group btn-group-sm` icon buttons (edit `bi-pencil` / delete
`bi-trash` with `data-{confirm}`). Title = display name.

### 2.3 Credit card card
- Title: `Bancolombia Visa` (+ `bi-credit-card-2-front`), subtitle `Credit Card · Bank`,
  identifier badge `badge bg-light text-dark` → `Visa · 1234`.
- **Credit available** headline: `fs-5 fw-bold text-success` big value +
  `span text-muted fw-normal fs-6` `of $20,000,000`. Available &gt; used → `text-success`;
  below a threshold (e.g. ≤20% remaining) → `text-danger` (see §5).
- Utilization bar: `progress` height `8px`, `role="progressbar"`, width = utilization %,
  color per `credit_utilization_class` (§5). Footer row flexbox: `Used $7,000,000`
  (strong `text-danger`) · `35%`.
- Meta row (`small text-muted`, `d-flex flex-wrap gap-2`): `bi-percent` `24.5% EA`,
  `bi-calendar-event` `Statement: 15`, `bi-calendar-check` `Due: 30`.
- Tags + `transactions` count as today.

Never display card number, CVV or PIN.

### 2.4 Loan card
- Title: `Kia Seltos Loan` (+ `bi-cash-coin`), subtitle `Loan · {lender}`.
- **Outstanding balance** headline: `fs-5 fw-bold text-danger`.
- Repayment bar (`progress`, `bg-success`, width = `repayment_progress` %) with footer
  `Original $114,000,000` · `42% repaid`.
- Meta row: `bi-percent` `21.27% EA`, `bi-cash-stack` `$2,686,800 / month`.
- `bi-arrow-repeat` `42 of 72 installments remaining`.
- Tags + tx count. Unmistakably debt: big red amount + "Outstanding balance" label.

## 3. Money source show (detail)

Keep existing Details + Tags cards for all kinds. For debt sources add a prominent debt
panel using the same `row g-4` layout (`col-lg-7` panel, `col-lg-5` details/tags).

### 3.1 Credit card panel
- Header: kind badge + `Visa · 1234` + issuer badges; right-aligned **Current debt**
  `fs-4 fw-bold text-danger`.
- Approved / Used / Available strip: `row text-center g-0`, three `col-4` with `fs-5 fw-bold`
  values and `small text-muted` labels (Approved plain, Used `text-danger`, Available
  `text-success`), separated by `border-start`.
- Utilization `progress` (10px) + `small text-muted` `Used: 35% of approved credit`.
- Billing alert: `alert alert-warning` `py-2 px-3 small` →
  "Next statement on the 15th, payment due on the 30th."
- Details `dl`: Type, Issuer, Brand, Last four digits, Interest rate (badge `bg-primary`
  `24.5% EA`), Statement day, Payment due day, Status (`badge bg-success` Active).

### 3.2 Credit card installments
Installments belong to the **financed transaction**, never the card. Full-width table card
below the two-column row, shown only when the card has installment transactions:
- `table table-hover align-middle`, `thead table-light`, `table-responsive` wrapper.
- Columns: Purchase (desc + category badge), Date, Original amount, Installment
  (`4 / 12`), Installment amount, Remaining balance (`text-danger`), Status
  (`badge bg-primary` Active).
- Caption: installments belong to each transaction; purchases without installments aren't
  listed. Empty state: muted centered `No active installments.`

### 3.3 Loan panel
- Header: `Loan` badge + lender; right-aligned **Outstanding balance**
  `fs-4 fw-bold text-danger`.
- Original principal / Monthly payment strip: two `col-6` as in §3.1.
- Repayment `progress` (10px, `bg-success`) + `42% of principal repaid · 42 of 72
  installments remaining`.
- Info alert `alert-warning`: "This is debt. Payments reduce the outstanding balance…".
- Details `dl`: Type, Lender, Interest rate badge, Installment amount, Installment count,
  Payment frequency (`bi-calendar-week`), Start date, End date, Remaining installments,
  Status.

## 4. Create / Edit form (`_form.html.erb`)

Existing card container (`card-header bg-primary text-white`, `card-body`), error summary
`alert alert-danger`, inline `is-invalid`/`invalid-feedback` via `field_class`/`field_error`,
money inputs with `$` input-group + `money_field_value`, submit `btn btn-primary` in
`d-grid`. Tags block unchanged.

**Kind-conditional panels.** The `kind` select already exists; add
`data-kind-panel="..."` wrappers (`<div data-kind-panel="account cash wallet">` etc.).
A small inline script (same pattern as the existing tag-row script in the partial) toggles
`el.hidden` on change; on load it applies the current kind. Only the fields relevant to the
selected kind render.

| Kind(s) | Panel fields |
|---|---|
| account / cash / wallet | Bank, Starting balance |
| debit_card | Bank, Linked-to parent select (accounts & wallets only, existing) |
| credit_card | Bank / Issuer, Card brand (select: Visa, Mastercard, Amex, Other), Last four digits, Credit limit ($), Interest rate (%), Interest rate type (EA / NA / Monthly), Statement day (1–31), Payment due day (1–31) |
| loan | Lender, Original principal ($), Interest rate (%), Interest rate type, Installment amount ($), Installment count (min 1), Payment frequency (weekly / biweekly / monthly / quarterly), Start date, End date |

- Common: Name, Type, Active checkbox, Tags. Debit/credit/loan panels do **not** show
  Starting balance (used credit / outstanding derive from transactions).
- `form-text` hints: "Never store the full card number, CVV or PIN." (last-four);
  "Recurring billing cycle days of the month (1–31)." (day fields).
- Rate inputs use `%` suffix inside `input-group`.

## 5. Progress bars & utilization coloring

Shared helper `credit_utilization_class(pct)` (ApplicationHelper), used for credit bars and
repayment bars:

| Utilization % | Bar class |
|---|---|
| 0–49% (or repaid &lt; 50%) | `bg-success` |
| 50–80% | `bg-warning` |
| &gt; 80% | `bg-danger` |

All bars: `<div class="progress" … role="progressbar" aria-valuenow aria-valuemin
aria-valuemax style="height: 8px"/10px">` + inner `progress-bar`. Color is a secondary cue;
label text ("Used 35%" / "42% repaid") always accompanies it.

## 6. Related selectors (expense / income / transfer forms)

The money-source `<select>` used by expense, income, recurring and transfer forms gains a
`Loan (debt)` optgroup; credit cards remain grouped under debt. Optgroups:
Accounts &amp; Wallets · Debit Cards (linked) · Credit Cards (debt) · Loans (debt). Label
uses `display_name` (`Name · Bank · 1234`).

## 7. States

| State | Behavior |
|---|---|
| Empty (index) | Existing centered empty card + CTA; debt section hidden when no debt sources |
| Loading | Server-rendered ERB; no explicit skeleton (Turbo handles navigation) |
| Error (form) | Existing `alert-danger` summary + `is-invalid` fields + `invalid-feedback` per field; kind panels stay open so the user sees errors |
| Success | Existing flash `alert-success` (`money_sources.flashes.*`) → back to index |
| Inactive source | Existing `badge bg-secondary` "Inactiva"; card content unchanged |
| Delete debt source with history | Existing confirm dialog; transactions remain (`dependent: :nullify`) |

## 8. Responsive behavior

- Index grid: one column on xs → two on `md` → three on `lg` (existing `col-12 col-md-6
  col-lg-4`). Section headers/captions stack with `mt-*` spacing.
- Detail: `row g-4`, panels stack on mobile (`col-lg-7`/`col-lg-5`); the strip stays
  `row`/`col-*` so it wraps naturally on tiny screens; installments use `table-responsive`
  (horizontal scroll on mobile).
- Form: 2-col fields at `md+`, 1-col on xs; header buttons wrap (`flex-wrap gap-2`).
- Cards: keep actions icon-only so they don't wrap on narrow columns.

## 9. Accessibility

- Progress bars carry `role="progressbar"` + `aria-valuenow/min/max` + descriptive
  `aria-label` ("Credit used", "Loan repaid").
- Icon-only edit/delete/brand buttons: `title` + `aria-label` with the source name.
- Debt is never conveyed by color alone: red amounts are always paired with a word label
  ("Used", "Outstanding balance", "Debt").
- Form labels: `for`/`id`; hints via `aria-describedby`; errors via `aria-describedby` +
  `invalid-feedback`.
- Tables have a heading row + `caption` (visually-hidden) describing content.
- Kind panel changes: triggered by a native `<select>` change, so keyboard/focus order is
  preserved; hidden panels use the `hidden` attribute (removed from a11y tree).

## 10. i18n keys to add (`config/locales/es.yml` default, and `en.yml`)

- `kinds.loan` → "Préstamo" / "Loan"
- `money_sources.index.: assets_section, debts_section, debts_caption, available_credit,
  approved_credit, used_credit, current_debt, credit_of_%{available}…of %{limit},
  outstanding_balance, original_amount, repayment_progress (%{pct}% repaid),
  installment_amount, remaining_installments (%{count} of %{total}),
  payment_frequency, rate_ea / rate_na / rate_m, statement_day, payment_due_day,
  credit_utilization (%{pct}% of approved credit)`
- `money_sources.show.: statement_alert, loan_debt_alert, active_installments,
  installments_caption, no_installments, remaining`
- `money_sources.form.: bank_issuer, lender, card_brand, card_brand_options.*, last_four,
  last_four_hint, credit_limit, interest_rate, interest_rate_type, rate_type_*,
  statement_day, payment_due_day, day_hint, original_principal, installment_amount,
  installment_count, payment_frequency, frequency_*, start_date, end_date`
- Validation messages reuse `activerecord.errors.models.*` conventions.

## 11. Implementation notes for the developer

- **Model/DB**: add `loan` to `MoneySource::KINDS`; new `CreditAccount` table
  (`credit_limit`, `interest_rate`, `interest_rate_type`; credit-card: `card_brand`,
  `card_last_four`; loan: `principal_amount`, `outstanding_balance`, `installment_amount`,
  `installment_count`, `payment_frequency`, `start_date`, `end_date`; billing:
  `statement_day`, `payment_due_day`). `MoneySource has_one :credit_account`. No
  product-specific nullable columns on `money_sources`. Credit-card identification uses
  `card_brand`/`card_last_four`/issuer (`bank`) — never full number/CVV/PIN. Installments
  live on the financed transaction, not the card (design ready for interest-free /
  interest-bearing / early payment).
- **Balance math**: keep account/cash/wallet/debit behavior; debt sources derive
  `used_credit`/`outstanding_balance` from transactions (not duplicated stored values where
  possible); `available_credit = credit_limit − used_credit`; sign convention in §1.
  Transfer in→credit/debt source reduces used credit / increases asset; out increases debt.
- **Validations**: kind-conditional required fields (credit card → `credit_limit`; loan →
  `principal_amount`, `interest_rate`), non-negative limits, valid rate type / frequency /
  statement &amp; due days (1–31) / installment counts (≥ 1). Asset kinds must not require
  credit-specific fields.
- **Transactions semantics** (backend of truth, no front-end calc): Purchase → increases
  used credit; Payment → decreases used credit; Refund → decreases used credit (and loan
  outstanding on refunds applies to loans); Interest charge / Fee → increases debt; Transfer
  from an account to a credit/loan source = payment (decreases debt, decreases account).
- **Backward compatibility**: existing kinds keep current behavior; seeds updated to add
  optional credit_card CreditAccount rows; update `db:seed` if it creates sources.
- **Tests**: MoneySource predicates (`credit_card?`, `loan?`, `debt?`), balance per kind,
  credit limit/used/available, statement/due days, interest rate, installment transactions,
  loan principal/outstanding/installments/frequency/balance, and a regression suite for
  account/debit/cash/wallet.

## 12. Files

- `app/models/money_source.rb`, new `app/models/credit_account.rb`
- `app/views/money_sources/index.html.erb` (grouped sections + variants),
  `show.html.erb` (debt panels), `_form.html.erb` (kind panels + script)
- `app/helpers/application_helper.rb` (`source_kind_icon` loan→`cash-coin`,
  `credit_utilization_class`) or new `MoneySourcesHelper`
- `config/locales/es.yml`, `en.yml`
- Layout `<style>` block: `.card-debt` accent (one rule)
- Seeds + specs as per §11.