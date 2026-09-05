# Expense Tracker — Models & Services Relationships

> Auto-generated reference. Grounded in `app/models/` and `app/services/`.
> Last generated: 2026-09-05.

---

## 1. Models & their relationships

### Association map

```
                            ┌────────────┐
                            │   User     │  (Devise auth)
                            └─────┬──────┘
        ┌──────────┬──────────┬───┴────┬──────────┬──────────┬──────────┐
        ▼          ▼          ▼        ▼          ▼          ▼          ▼
      Income    Expense   Transaction  Recurring  GmailCon  MoneySource FinancialSetup
                           (STI base)  Template   nection (1,2,3...)
        │          │          │
        ▼          ▼          ▼
      belongs_to :category ─────────┐
      belongs_to :money_source      │
      belongs_to :recurring_template
```

### Detailed relationships

#### User
Devise-authenticated owner of everything.
- **has_many:** `incomes`, `expenses`, `transactions`, `recurring_templates`, `gmail_connections`, `processed_emails`, `money_sources`, `transfers`, `financial_setups` (all `dependent: :destroy`)

#### Transaction (STI base)
The single money-movement record (`inheritance_column` disabled, so `kind` column drives `income`/`expense`). Amount is normalized to be **signed** (expense = negative).
- **belongs_to:** `user`, `category`; `recurring_template` (optional), `money_source` (optional)
- **Subclasses:** `Expense` (default_scope `expense`, adds `dashboard_summary`), `Income` (default_scope `income`, adds `dashboard_summary`)

#### Category
Hierarchical (self-referential `parent`/`children`), with default vs. custom categories and per-user/type uniqueness.
- **belongs_to:** `parent` (Category, optional), `user` (optional)
- **has_many:** `children` (Category), `expenses`, `incomes`, `transactions`, `recurring_templates` (all `dependent: :destroy` / `:nullify`)

#### MoneySource
A financial source (account / debit_card / credit_card / cash / wallet / loan). Balance computed from start + transactions + children + transfers. Debt kinds (credit_card, loan) surface `used_credit`, `available_credit`, `credit_utilization` via its CreditAccount.
- **belongs_to:** `user`, `parent` (MoneySource, optional)
- **has_many:** `children`, `transactions`, `recurring_templates`, `outgoing_transfers` (→Transfer), `incoming_transfers` (→Transfer)
- **has_one:** `credit_account` (CreditAccount, `dependent: :destroy`), `recognition` (MoneySourceRecognition)
- **has_many:** `recognition_identifiers` **through** `recognition`
- **Security:** `normalize_identifier_to_last_four` — only the last 4 digits of any account/card/loan number are ever stored.

#### CreditAccount
Credit/debt details for a `MoneySource` (credit limits, interest, installments, statement/payment days, card brand/last-four).
- **belongs_to:** `money_source` (one per source)

#### MoneySourceRecognition
Holds recognition config for a **single** MoneySource (optional; absent == "not configured"). Manages promote/dismiss of identifiers.
- **belongs_to:** `money_source`
- **has_many:** `recognition_identifiers` (MoneySourceRecognitionIdentifier)

#### MoneySourceRecognitionIdentifier
A single matching signal: `keyword` / `sender` / `domain` / `subject` / `header`, with lifecycle `status` (`confirmed` | `suggested`) and `origin` (`user` | `gmail`). Only **confirmed** identifiers are used for matching; suggestions are for review.
- **belongs_to:** `money_source_recognition`

#### RecurringTemplate
A monthly recurring income/expense config.
- **belongs_to:** `user`, `category`, `money_source` (optional)
- **has_many:** `transactions` (the occurrences it generated)

#### Transfer
Money moved between two sources.
- **belongs_to:** `user`, `from_source` (MoneySource), `to_source` (MoneySource)
- Validates `from_source != to_source`.

#### GmailConnection
A user's connected Gmail account (Google OAuth, tokens encrypted via `EncryptedSecret`). `fresh_access_token!` auto-refreshes.
- **belongs_to:** `user`
- `search_config` normalized via `search_config_hash` → used to build Gmail queries.

#### ProcessedEmail
Idempotency guard: every examined email recorded once per `[provider, message_id]` (race-safe unique index).
- **belongs_to:** `user`, `expense` (optional)
- Statuses: `processed` / `ignored` / `needs_review` / `failed`.

#### FinancialSetup
Persisted onboarding-wizard state (current step, per-step choice, draft sources, import state) so the user can resume.
- **belongs_to:** `user`

#### Seed catalog (standalone, no user)
- `FinancialInstitution` — Colombian institutions (aliases + domains) for the cheap email filter.
- `FinancialKeyword` — global financial keywords with category + signal weight.
- `FinancialSubjectPattern` — generic subject patterns signaling financial emails.
- Seeded idempotently from `db/seed_data/` by `FinancialCatalogSeeder`.

---

## 2. Services & their relationships

### Service call graph (high level)

```
                       ┌────────────────────┐
                       │  Gmail::SyncService │  (per-connection sync)
                       └─────────┬──────────┘
              ┌──────────────────┼──────────────────────┐
              ▼                  ▼                      ▼
  Gmail::QueryBuilder   Gmail::Client           SourceRecognition::
  (build search query)  (fetch messages)        DiscoveryService
                                                    │ suggestions
                                                    ▼
              ┌──────────────────────────────────────┼──────────────┐
              ▼                                      ▼              ▼
  EmailTransactionDetector                FinancialEmailFilter   Matcher / Catalog
  (cheap pre-filter)                              │
              │                                    ▼
              ▼                              TextNormalizer
  Gmail::ExpenseImporter
        │  per message:
        ▼
  Ai::TransactionExtractor ──► ParsedExpense-ish ──► Expenses::Create ──► Expense
        │
        ▼
  MoneySources::Match  /  SourceRecognition::Matcher   (resolve source)

  ── Statement import path ──────────────────────────────────────────
  ImportPipeline ──► Ai::StatementExtractor ──► ParsedStatement
        │
        ▼
  StatementDuplicateDetector ──► MoneySource
```

### Detailed service roles

| Service | What it does |
|---|---|
| **ExpenseParser** | Turns natural-language (text/voice) into **unsaved** expenses. AI (Mistral) when key set, else deterministic Colombian-amount heuristic parser. Returns `{engine, expenses[], errors}`. Uses `ParsedExpense`. |
| **ParsedExpense** | Value object for one parsed expense; validates before persistence. |
| **Expenses::Create** | **Single entry point** for creating an `Expense` from any source (manual / text / voice / gmail / ai). Normalizes amount, resolves category, raises `Invalid` on failure. |
| **ImportPipeline** | Orchestrates statement upload: validate → detect format → extract text (PDF/CSV/XLSX) → AI extraction → build `ParsedStatement` sources + transactions. Never writes records. |
| **Ai::StatementExtractor** | LLM (Mistral) that extracts financial **sources + transactions** from statement text with strict JSON output; enforces privacy (only last-4 of identifiers). |
| **Ai::TransactionExtractor** | LLM that extracts **transactions** from an email notification; decides `should_ignore` (statements/promos/security). |
| **ParsedStatement** | Value object for one extracted source row from an import. |
| **StatementDuplicateDetector** | Matches an extracted statement source against existing `MoneySource` (by unique identifier, or bank + last-four) to surface duplicates during review. |
| **RecurringTemplateImporter** | Bulk-imports recurring templates from a CSV. |
| **RecurringTemplateProcessor** | Converts a recurring config into a real one-time `Transaction`, guarded to run once per period, inside a DB transaction. |
| **ExpenseDashboardService** | Query service for dashboard: scoped expenses, `total_spent`, `categories_breakdown`. |
| **EmailTransactionDetector** | Cheap, no-AI pre-filter classifying an email as transactional / non-transactional (statements, promos, security) or special (refund/reversal/failed). |
| **FinancialSetupWizard** | Single source of truth describing ordered onboarding steps (cash, accounts, credit_cards, loans, review) and each step's kind/choice. |
| **FinancialSetups::Completer** | Creates real financial records (MoneySource/ CreditAccount/ RecurringTemplate) from the finished wizard's draft + import data, in one transaction. |
| **FinancialSetups::StepPresenter** | Builds the per-step "Added" summary (dedup of manual + import rows, display amount/label per kind) for the wizard view. |
| **MoneySources::Match** | Matches an incoming transaction to a `MoneySource` via tag/name, last-four or bank (recognition-aware); returns a single source, an array (ambiguous), or nil. |
| **Gmail::Client** | Thin Gmail API client: list + fetch one normalized message (headers, subject, plain-text body). |
| **Gmail::OauthClient** | Minimal Google OAuth2 (auth URL, code exchange, refresh, userinfo). |
| **Gmail::QueryBuilder** | Builds the Gmail search query (from senders/domains, subject keywords, lookback window, exclusions). |
| **Gmail::ExpenseImporter** | Processes **one** email: dedup → detector → AI extraction → source resolution → `Expenses::Create` (or review queue) → record outcome in `ProcessedEmail`. |
| **Gmail::SyncService** | Synchronizes one connection: builds query, fetches up to 25 messages, imports each (never aborting on a single failure), and runs recognition discovery. |
| **SourceRecognition::Catalog** | Read-only access to the seeded financial catalog (institutions, keywords, subject patterns, domain index). |
| **SourceRecognition::FinancialEmailFilter** | Cheap deterministic first-stage filter: scores domain/alias/keyword/pattern signals, rejects marketing, requires a transactional signal before passing to AI/discovery. |
| **SourceRecognition::Matcher** | Consumption side: matches a fetched email against **confirmed** recognition identifiers of the user's sources; returns winning source / ambiguous array / nil. |
| **SourceRecognition::DiscoveryService** | Gmail-based suggestion discovery: filters email, finds candidate sources, persists **suggested** identifiers (sender/domain/subject/keywords) without touching confirmed ones. |
| **SourceRecognition::SuggestionEngine** | Computes **non-persisted** suggestions (from Gmail-provenance, source name/bank, sibling sources) to pre-fill the recognition page. |
| **SourceRecognition::ApplyToSearchConfig** | Feeds **confirmed** recognition values back into the Gmail connection's `search_config`, narrowing future sync queries (the "first-sync setup accelerator" loop). |
| **SourceRecognition::TextNormalizer** | Accent-insensitive, word-boundary text folding used across source recognition. |
| **MoneyFormat** | Normalizes money strings between Colombian display (`97.254.852,58`) and machine (`972548.58`) formats. |

---

## 3. Key cross-cutting relationships

| From | Relation | To |
|---|---|---|
| `ExpenseParser` | uses | `ParsedExpense`, `Category`, `MoneySource` (+ recognition identifiers) |
| `Expenses::Create` | creates | `Expense` (via `Category`) |
| `ImportPipeline` | orchestrates | `Ai::StatementExtractor`, `ParsedStatement` |
| `Ai::StatementExtractor` | normalizes into | `ParsedStatement` fields |
| `StatementDuplicateDetector` | matches against | `MoneySource` |
| `FinancialSetups::Completer` | consumes | `FinancialSetupWizard`, `ParsedStatement`, `StatementDuplicateDetector`, creates `MoneySource` / `CreditAccount` / `RecurringTemplate` |
| `FinancialSetups::StepPresenter` | reads | `FinancialSetup` draft/import state |
| `RecurringTemplateProcessor` / `Importer` | produce/consume | `RecurringTemplate` → `Transaction` |
| `Gmail::ExpenseImporter` | uses | `EmailTransactionDetector`, `Ai::TransactionExtractor`, `SourceRecognition::Matcher`, `MoneySources::Match`, `Expenses::Create`, `ProcessedEmail` |
| `Gmail::SyncService` | uses | `Gmail::QueryBuilder`, `Gmail::Client`, `Gmail::ExpenseImporter`, `SourceRecognition::DiscoveryService`, `ProcessedEmail` |
| `SourceRecognition::DiscoveryService` | uses | `FinancialEmailFilter`, `Matcher`, `Catalog`, `TextNormalizer`, persists `MoneySourceRecognitionIdentifier` (suggested) |
| `SourceRecognition::Matcher` | reads | `MoneySource` recognition identifiers (confirmed only) |
| `SourceRecognition::ApplyToSearchConfig` | writes | `GmailConnection#search_config` |
| `FinancialEmailFilter` | reads | `FinancialInstitution`, `FinancialKeyword`, `FinancialSubjectPattern` (via `Catalog`) |
| `MoneySources::Match` | reads | `MoneySource` recognition + `CreditAccount` (card last four) |

---

## 4. Data-flow story

1. **Manual / text / voice entry** → `ExpenseParser` → `ParsedExpense` → `Expenses::Create` → `Expense`.
2. **Gmail import** → `Gmail::SyncService` → fetch via `Gmail::Client`/`QueryBuilder` → `EmailTransactionDetector` filter → `Ai::TransactionExtractor` → `Gmail::ExpenseImporter` resolves source → `Expenses::Create` → `Expense` + `ProcessedEmail` (idempotency).
3. **Statement upload** → `ImportPipeline` → `Ai::StatementExtractor` → `ParsedStatement` — reviewed, deduped via `StatementDuplicateDetector`, committed by `FinancialSetups::Completer` → `MoneySource` / `CreditAccount` / `RecurringTemplate`.
4. **Recurring payments** → `RecurringTemplateProcessor` (period-guarded) or CSV via `RecurringTemplateImporter`.
5. **Source recognition feedback loop** → Gmail sync discovers **suggestions** → user confirms → `ApplyToSearchConfig` narrows future Gmail queries → `Matcher` auto-resolves future sources.
