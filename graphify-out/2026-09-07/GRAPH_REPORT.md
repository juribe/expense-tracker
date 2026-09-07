# Graph Report - expense-tracker  (2026-09-07)

## Corpus Check
- 271 files · ~138,825 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1783 nodes · 2216 edges · 205 communities (66 shown, 112 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 57 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `8ef68c4f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- GmailConnectionsController
- ExpensesController
- ExpenseParser
- auth.js
- MoneySource
- Gmail::ExpenseImporterTest
- Category Management UI/UX Spec
- Ai::StatementExtractor
- FinancialSetupsController
- ParsedStatement
- Gmail::ExpenseImporter
- application.js
- Ai::TransactionExtractor
- Bulk Update Expense Category and Money Source
- ApplicationHelper
- RecurringTemplate
- SourceRecognition::Matcher
- SourceRecognition::SuggestionEngine
- MoneySourcesController
- Gmail::QueryBuilder
- QaValidateDashboardReportsController
- Category Data Model
- Category
- Expenses::Create
- FinancialSetups::Completer
- SourceRecognition::DiscoveryService
- Source Recognition (Gmail-based Email Matching)
- RecurringTemplateActions
- FinancialSetup
- FinancialSetups::StepPresenter
- Gmail::Client
- Gmail::SetupScanService
- MoneySourceRecognitionIdentifier
- Gmail::SetupScanServiceTest::FakeClient
- IncomesController
- Detailed relationships
- CreditAccount
- createCategory
- Expense Model
- Hybrid Financial Setup Wizard
- ApplicationController
- RecurringTemplateImporter
- ExpensesHelper
- Budget
- Credit Cards and Loans
- Support Monthly Income and Payments
- financial_setup_wizard.rb
- Source Recognition Implementation Guide
- TransfersController
- Money Sources Definition
- Expense Views Table
- Implementation
- MigrateTagsToRecognitionIdentifiers
- Category Management Design
- package.json
- StatementDuplicateDetector
- ExpenseDashboardService
- Bulk Update Expense Category and Money Source
- 400 Bad Request Error Page
- ImportPipelineTest
- SourceRecognition::DiscoveryServiceTest
- ActiveSupport::TestCase
- Devise Authentication Forms
- playwright.config.js
- oauth_client.rb
- Users::PasswordsController
- Users::RegistrationsController
- DashboardHelper
- MoneySource (Accounts, Credit Cards, Loans)
- ExpensesControllerTest
- CompleterTest
- FinancialSetups::StepPresenterTest
- SourceRecognition::ApplyToSearchConfigTest
- SourceRecognition::FinancialEmailFilterTest
- ExpenseTracker
- AddDeviseToUsers
- AddCategoryFormFields
- BackfillTransactionsAndTemplates
- RemapLegacyLinksToTransactions
- NormalizeTransactionSigns
- RemoveFrequencyFromTransactions
- DropMonthlyExpenseAndRecurringTransactionTables
- MigrateMoneySourceIdentifiersToTags
- MoneySourcesControllerTest
- GmailSyncJobTest
- FinancialSetupTest
- MoneySourceRecognitionTest
- MoneySourceTest
- Application Brand Icon
- ApplicationMailer
- Alertas de gasto — UI/UX Design Specification
- CreateCategories
- CreateExpenses
- CreateUsers
- CreateIncomes
- CreateMonthlyExpensePayments
- CreateRecurringTransactions
- CreateRecurringTransactionOccurrences
- CreateMonthlyExpenses
- CreateTransactions
- CreateRecurringTemplates
- AddFrequencyToTransactions
- CreateGmailConnections
- CreateProcessedEmails
- AddGmailMessageIdToTransactions
- CreateMoneySources
- CreateMoneySourceIdentifiers
- CreateTransfers
- AddMoneySourceIdToTransactions
- AddMoneySourceIdToRecurringTemplates
- AddDefaultAndCustomToCategories
- ScopeCategoryUniqueness
- CreateSolidQueueTables
- CreateMoneySourceTags
- AddIdentifierToMoneySources
- AddValueIndexToMoneySourceTags
- DropMoneySourceIdentifiers
- CreateCreditAccounts
- CreateFinancialSetups
- AddInstallmentsPaidToCreditAccounts
- CreateMoneySourceRecognitions
- CreateFinancialEmailCatalog
- AddDiscoveryStateToRecognitionIdentifiers
- AddSyncStateToGmailConnections
- Category Management
- CategoriesControllerTest
- ExpensesAiEntryTest
- GmailConnectionsControllerTest
- SessionsControllerTest
- ApplicationHelperTest
- DeviseAuthFlowsTest
- CategoryTest
- CreditAccountTest
- FinancialInstitutionTest
- GmailConnectionTest
- ProcessedEmailTest
- FinancialSetupWizardTest
- ParsedStatementTest
- docker-entrypoint
- Devise English Translations
- English Application Translations
- @playwright/test
- Presupuesto por categoría — UI/UX Design Specification
- ImportPipeline
- RecurringTemplatesController
- recurring_template_processor.rb
- AlertsController
- BudgetsHelper
- alerts.spec.js
- budgets.spec.js
- Transfer
- MoneySourceRecognition
- Transaction
- graphify.js
- AGENTS.md
- ai_entry_turbo.spec.js
- ApplicationRecord
- GmailSyncJob
- ApplicationJob
- Gmail::OauthClient
- GmailConnection
- financial_setup_wizard.spec.js
- EncryptedSecret
- money_source_tags.spec.js
- GmailSetupSyncJobTest
- AddSetupSuggestionsToGmailConnections
- AlertsHelper
- CreateSpendingAlerts
- opencode.json
- ai_money_source_detection.spec.js
- CreateAlertPreferences
- CascadeDeleteProcessedEmailsOnExpense
- CreateBudgets
- AlertSettingsControllerTest
- AlertsControllerTest
- BudgetsControllerTest
- AlertPreferenceTest
- SpendingAlertTest

## God Nodes (most connected - your core abstractions)
1. `ExpensesController` - 34 edges
2. `Category` - 33 edges
3. `FinancialSetupsController` - 32 edges
4. `ExpenseParser` - 32 edges
5. `MoneySource` - 29 edges
6. `Ai::StatementExtractor` - 28 edges
7. `ApplicationHelper` - 25 edges
8. `@playwright/test` - 25 edges
9. `Ai::TransactionExtractor` - 22 edges
10. `GmailConnectionsController` - 21 edges

## Surprising Connections (you probably didn't know these)
- `Source Recognition (Gmail-based Email Matching)` --references--> `Colombian Financial Institutions Catalog`  [INFERRED]
  EXPLORATION_SUMMARY.md → db/seed_data/financial_institutions.yml
- `Expense List & Filters Design` --semantically_similar_to--> `Expense Views Table Design`  [INFERRED] [semantically similar]
  designs/design_expense_list_filters.md → designs/design_expense_views_table.md
- `Expense List and Filters Design` --semantically_similar_to--> `Expense Views Table`  [INFERRED] [semantically similar]
  mockups/design_expense_list_filters.html → mockups/design_expense_views_table.html
- `Gmail Integration I18n Keys (English)` --implements--> `Source Recognition (Gmail-based Email Matching)`  [EXTRACTED]
  config/locales/en.yml → EXPLORATION_SUMMARY.md
- `Source Recognition (Gmail-based Email Matching)` --references--> `Financial Email Keywords Dictionary`  [INFERRED]
  EXPLORATION_SUMMARY.md → db/seed_data/financial_keywords.yml

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Credit Card & Loan Debt Source Flow** — designs_credit_cards_and_loans_loan_kind, designs_credit_cards_and_loans_creditaccount, designs_design_develop_hybrid_financial_setup_wizard_financialsetupwizard, designs_design_definition_money_sources_accounts_cards_wallets_transfers_matching_moneysources [EXTRACTED 0.85]
- **Core Expense Domain Model Graph** — exploration_summary_expense_model, exploration_summary_category_model, exploration_summary_user_model, exploration_summary_monthly_expense_model, exploration_summary_monthly_expense_payment_model [EXTRACTED 1.00]
- **Rails Default Error Page Template Family** — public_400_html, public_404_html, public_406_unsupported_browser_html, public_422_html, public_500_html [EXTRACTED 1.00]
- **Bilingual I18n Layer (English/Spanish)** — config_locales_devise_en, config_locales_devise_es, config_locales_en, config_locales_es [EXTRACTED 1.00]
- **Source Recognition Feature** — docs_source_recognition_implementation_md_money_source_recognition, docs_source_recognition_implementation_md_suggestion_engine, docs_source_recognition_implementation_md_recognition_controller, docs_source_recognition_implementation_md_gmail_guard [EXTRACTED 1.00]
- **Category Selection Pattern** — docs_designs_design_add_expense_form_md_category_dropdown, docs_designs_design_category_management_md, docs_designs_design_dashboard_ui_ux_md_filter_bar [INFERRED 0.75]
- **Money Source Lifecycle** — mockups_credit_cards_and_loans_moneysourceindex, mockups_credit_cards_and_loans_moneysourceform, mockups_design_definition_money_sources_accounts_cards_wallets_transfers_matching_moneysourcesindex, mockups_design_develop_hybrid_financial_setup_wizard_manualentry, concept_money_source_data_model [INFERRED 0.80]
- **Category Management Workflow** — mockups_category_form_design_and_implementation_categoryform, mockups_design_category_management_categorygrouplist, mockups_design_category_management_categorylist, concept_category_data_model [INFERRED 0.85]
- **Email-Based Financial Transaction Matching System** — db_seed_data_financial_institutions, db_seed_data_financial_keywords, db_seed_data_financial_subject_patterns, exploration_summary_source_recognition, gmail_sync_job_rationale [INFERRED 0.85]
- **Expense CRUD Operations** — mockups_bulk_update_expense_category_and_money_source_expensetable, mockups_design_add_expense_form_expenseform, mockups_design_expense_views_table_expensetable, concept_expense_data_model [INFERRED 0.85]
- **Expense Entry Workflow** — docs_designs_design_add_expense_form_md, docs_designs_design_add_expense_form_md_validation_states, docs_designs_design_add_expense_form_md_category_dropdown, docs_designs_review_expense_form_design_md, docs_mockups_review_expense_form_design_html [INFERRED 0.85]
- **Expenses Index Surface (Table/Filters/Bulk)** — designs_design_expense_views_table_expenseviewstable, designs_design_expense_list_filters_expenselistfilters, designs_bulk_update_expense_category_and_money_source_bulkupdate [INFERRED 0.85]
- **Public Static Web Assets** — public_400_html, public_404_html, public_406_unsupported_browser_html, public_422_html, public_500_html, public_robots_txt, public_icon_png, public_icon_svg [INFERRED 0.85]
- **Application Icon in Multiple Formats** — public_icon_png, public_icon_svg, app_brand_icon [INFERRED 0.90]

## Communities (205 total, 112 thin omitted)

### Community 1 - "ExpensesController"
Cohesion: 0.05
Nodes (8): ExpensesController, Expense, BudgetsFlowTest, IntegrationTest, BudgetTest, TestCase, CategorySpendTest, TestCase

### Community 2 - "ExpenseParser"
Cohesion: 0.07
Nodes (8): call(), ExpenseParser, ExpenseParser::AIError, ExpenseParser::Resolution, StandardError, ParsedExpense, ExpenseParserTest, TestCase

### Community 3 - "auth.js"
Cohesion: 0.14
Nodes (12): { signUp, signIn }, { test, expect }, { signUp }, { test, expect }, { signUp, createCategory }, { test, expect }, { signUp, createCategory }, { test, expect } (+4 more)

### Community 4 - "MoneySource"
Cohesion: 0.06
Nodes (7): MoneySource, MoneySources, MoneySources::Match, SanitizeMoneySourceIdentifiersToLastFour, MoneySources, MoneySources::MatchTest, TestCase

### Community 5 - "Gmail::ExpenseImporterTest"
Cohesion: 0.10
Nodes (9): EmailTransactionDetector, EmailTransactionDetector::Result, EmailTransactionDetectorTest, TestCase, Gmail, Gmail::ExpenseImporterTest, Gmail::ExpenseImporterTest::FakeDetector, Gmail::ExpenseImporterTest::FakeExtractor (+1 more)

### Community 6 - "Category Management UI/UX Spec"
Cohesion: 0.06
Nodes (38): Add Expense Form Design Spec, Bootstrap 5 Components, Category Dropdown, Centered Modal or Card Layout, Bootstrap 5 Color Palette, Form Validation States, Category Management UI/UX Spec, Custom Category Grouping (+30 more)

### Community 7 - "Ai::StatementExtractor"
Cohesion: 0.10
Nodes (8): Ai, Ai::StatementExtractor, Ai::StatementExtractor::ExtractionError, parse(), StandardError, Ai, Ai::StatementExtractorTest, TestCase

### Community 9 - "ParsedStatement"
Cohesion: 0.12
Nodes (6): ImportPipeline::Result, ParsedStatement, FinancialSetupsControllerTest, IntegrationTest, TestCase, StatementDuplicateDetectorTest

### Community 10 - "Gmail::ExpenseImporter"
Cohesion: 0.06
Nodes (13): ProcessedEmail, Gmail, Gmail::ExpenseImporter, Gmail::ExpenseImporter::Result, call(), Gmail, Gmail::SyncService, configure() (+5 more)

### Community 11 - "application.js"
Cohesion: 0.12
Nodes (25): bindAvailableCredit(), bindForm(), bindInput(), bindRecognition(), formatCurrencyNumber(), formatInput(), formatValue(), gmailSyncStatusPath() (+17 more)

### Community 12 - "Ai::TransactionExtractor"
Cohesion: 0.11
Nodes (8): Ai, Ai::TransactionExtractor, Ai::TransactionExtractor::ExtractionError, parse(), StandardError, Ai, Ai::TransactionExtractorTest, TestCase

### Community 13 - "Bulk Update Expense Category and Money Source"
Cohesion: 0.08
Nodes (27): Bulk Bar (Expenses index), Bulk Update Expense Category and Money Source, category_badge Helper, ExpensesController#bulk_update, MoneySource.active Scope, MoneySource#display_name, Recurring Transactions UI (Income & Expense), Monthly Recurring Expenses UI (+19 more)

### Community 16 - "SourceRecognition::Matcher"
Cohesion: 0.13
Nodes (6): call(), SourceRecognition, SourceRecognition::Matcher, TestCase, SourceRecognition, SourceRecognition::MatcherTest

### Community 17 - "SourceRecognition::SuggestionEngine"
Cohesion: 0.11
Nodes (6): SourceRecognition, SourceRecognition::SuggestionEngine, SourceRecognition::SuggestionEngine::Suggestion, TestCase, SourceRecognition, SourceRecognition::SuggestionEngineTest

### Community 18 - "MoneySourcesController"
Cohesion: 0.10
Nodes (5): MoneySourcesController, MoneyFormat, call(), SourceRecognition, SourceRecognition::ApplyToSearchConfig

### Community 19 - "Gmail::QueryBuilder"
Cohesion: 0.11
Nodes (6): build(), Gmail, Gmail::QueryBuilder, Gmail, Gmail::QueryBuilderTest, TestCase

### Community 21 - "Category Data Model"
Cohesion: 0.16
Nodes (18): Category Data Model, Expense Data Model, Dashboard Example, Category Breakdown Chart, Recent Transactions List, Dashboard Stat Cards, Add Expense Form Design, Expense Entry Form (+10 more)

### Community 23 - "Expenses::Create"
Cohesion: 0.15
Nodes (7): Expenses, Expenses::Create, Expenses::Create::Invalid, StandardError, Expenses, Expenses::CreateTest, TestCase

### Community 24 - "FinancialSetups::Completer"
Cohesion: 0.19
Nodes (3): FinancialSetups, FinancialSetups::Completer, FinancialSetups::Completer::Result

### Community 25 - "SourceRecognition::DiscoveryService"
Cohesion: 0.05
Nodes (16): FinancialInstitution, FinancialKeyword, FinancialSubjectPattern, SourceRecognition, SourceRecognition::Catalog, call(), SourceRecognition, SourceRecognition::DiscoveryService (+8 more)

### Community 26 - "Source Recognition (Gmail-based Email Matching)"
Cohesion: 0.13
Nodes (17): ActionCable Configuration, PostgreSQL Database Configuration, Gmail Integration I18n Keys (English), Solid Queue Configuration, Recurring Tasks Configuration, ActiveStorage Configuration, Colombian Financial Institutions Catalog, Financial Email Keywords Dictionary (+9 more)

### Community 30 - "Gmail::Client"
Cohesion: 0.19
Nodes (4): Gmail, Gmail::Client, Gmail::Client::Error, StandardError

### Community 31 - "Gmail::SetupScanService"
Cohesion: 0.23
Nodes (3): call(), Gmail, Gmail::SetupScanService

### Community 33 - "Gmail::SetupScanServiceTest::FakeClient"
Cohesion: 0.18
Nodes (5): configure(), Gmail, Gmail::SetupScanServiceTest, Gmail::SetupScanServiceTest::FakeClient, TestCase

### Community 34 - "IncomesController"
Cohesion: 0.18
Nodes (3): DashboardController, IncomesController, Income

### Community 35 - "Detailed relationships"
Cohesion: 0.09
Nodes (22): 1. Models & their relationships, 2. Services & their relationships, 3. Key cross-cutting relationships, 4. Data-flow story, Association map, Category, CreditAccount, Detailed relationships (+14 more)

### Community 37 - "createCategory"
Cohesion: 0.18
Nodes (7): { signUp, createCategory }, { test, expect }, { signUp, createCategory }, { test, expect }, createCategory(), { signUp, createCategory }, { test, expect }

### Community 38 - "Expense Model"
Cohesion: 0.24
Nodes (12): Categories I18n Keys (English), Expenses I18n Keys (English), Categories I18n Keys (Spanish), Expenses I18n Keys (Spanish), Category Model (Nested Hierarchy), Dashboard (Summary Cards, Quick Add, Recent Expenses), Devise Authentication Rationale, Expense Model (+4 more)

### Community 39 - "Hybrid Financial Setup Wizard"
Cohesion: 0.17
Nodes (12): Money Source Form, Hybrid Financial Setup Wizard, Setup Complete State, Duplicate Card Handling, Extraction Review Step, Statement File Upload, Final Review Step, Manual Account Entry (+4 more)

### Community 40 - "ApplicationController"
Cohesion: 0.12
Nodes (5): AlertSettingsController, ApplicationController, Base, MonthlyIncomesController, MonthlyReportsController

### Community 43 - "Budget"
Cohesion: 0.06
Nodes (7): BudgetsController, Budget, SpendingAlert, CategorySpend, SpendingAlertService, TestCase, SpendingAlertServiceTest

### Community 44 - "Credit Cards and Loans"
Cohesion: 0.18
Nodes (11): Debt Visualization Pattern, Sidebar Navigation Pattern, Credit Cards and Loans, Active Installments Table, Assets and Money Group, Credit and Debt Group, Credit Card Detail View, Credit Utilization Bar (+3 more)

### Community 45 - "Support Monthly Income and Payments"
Cohesion: 0.24
Nodes (11): Recurring Transaction Data Model, Support Monthly Income and Payments, Expense Tab, Income Tab, Pay Expense Modal, Receive Income Modal, Recurring Transactions Tab, Support Monthly Recurring Expenses (+3 more)

### Community 46 - "financial_setup_wizard.rb"
Cohesion: 0.22
Nodes (3): choice?(), FinancialSetupWizard::Step, valid_choice!()

### Community 47 - "Source Recognition Implementation Guide"
Cohesion: 0.31
Nodes (10): Source Recognition Implementation Guide, Recognition Edit Panel, Gmail Connection Guard, MoneySourceRecognition Data Model, MoneySourceRecognitionIdentifier Data Model, Recognition Configured Predicate, Recognition Controller Action, Suggestion Chips UI (+2 more)

### Community 49 - "Money Sources Definition"
Cohesion: 0.25
Nodes (9): Gmail Import and Matching Flow, Money Source Data Model, Transfer Data Model, Wizard Multi-Step Pattern, Money Sources Definition, Gmail Import Review Queue, Money Sources Index View, Source Chooser for Forms (+1 more)

### Community 50 - "Expense Views Table"
Cohesion: 0.22
Nodes (9): State Management Pattern, Expense Views Table, Bulk Action Bar, CSV Export, Delete Confirmation Modal, Expense Detail Drawer, Expense Table with Sorting, Filter Chips (+1 more)

### Community 51 - "Implementation"
Cohesion: 0.18
Nodes (10): 1. `Gmail::SetupScanService`, 2. Wrong-data fixes in `SourceRecognition::DiscoveryService`, 3. Job + controller, 4. UI, Design: Gmail Setup Sync (first-sync setup accelerator), Goal, Implementation, Non-goals (+2 more)

### Community 52 - "MigrateTagsToRecognitionIdentifiers"
Cohesion: 0.43
Nodes (5): MigrateTagsToRecognitionIdentifiers, MigrateTagsToRecognitionIdentifiers::MigrationIdentifier, MigrateTagsToRecognitionIdentifiers::MigrationRecognition, MigrateTagsToRecognitionIdentifiers::MigrationTag, Base

### Community 53 - "Category Management Design"
Cohesion: 0.25
Nodes (8): Category Form Design and Implementation, Category Create Edit Form, Category Management Design, Add Category Modal, Add Group Modal, Category Group List, Category List, Delete Group Confirmation Modal

### Community 54 - "package.json"
Cohesion: 0.29
Nodes (6): devDependencies, @playwright/test, name, private, scripts, test:e2e

### Community 57 - "Bulk Update Expense Category and Money Source"
Cohesion: 0.29
Nodes (7): Bulk Operations Pattern, Bulk Update Expense Category and Money Source, Bulk Actions Bar, Change Category Modal, Expense Table, Change Money Source Modal, Expense Filter Form

### Community 58 - "400 Bad Request Error Page"
Cohesion: 0.48
Nodes (7): 400 Bad Request Error Page, 404 Not Found Error Page, 406 Unsupported Browser Error Page, 422 Unprocessable Entity Error Page, 500 Internal Server Error Page, Robots.txt Web Crawler Configuration, Rails Default Error Page Template Pattern

### Community 59 - "ImportPipelineTest"
Cohesion: 0.29
Nodes (3): ImportPipelineTest, ImportPipelineTest::FakeExtractor, TestCase

### Community 60 - "SourceRecognition::DiscoveryServiceTest"
Cohesion: 0.29
Nodes (3): TestCase, SourceRecognition, SourceRecognition::DiscoveryServiceTest

### Community 62 - "Devise Authentication Forms"
Cohesion: 0.33
Nodes (6): Authentication Flow, Devise Authentication Forms, Forgot Password Form, Reset Password Form, Sign In Form, Sign Up Form

### Community 63 - "playwright.config.js"
Cohesion: 0.33
Nodes (5): { defineConfig }, fs, path, rubyVersionFile, rvm

### Community 64 - "oauth_client.rb"
Cohesion: 0.29
Nodes (9): authorize_url(), configured?(), exchange_code(), parse_token_response(), perform(), post_token(), raise_configuration_error!(), refresh() (+1 more)

### Community 68 - "MoneySource (Accounts, Credit Cards, Loans)"
Cohesion: 0.40
Nodes (5): Money Sources I18n Keys (English), Wizard I18n Keys (English), MoneySource (Accounts, Credit Cards, Loans), Transfer Between Money Sources, Financial Setup Wizard

### Community 71 - "FinancialSetups::StepPresenterTest"
Cohesion: 0.40
Nodes (3): FinancialSetups, FinancialSetups::StepPresenterTest, TestCase

### Community 72 - "SourceRecognition::ApplyToSearchConfigTest"
Cohesion: 0.40
Nodes (3): TestCase, SourceRecognition, SourceRecognition::ApplyToSearchConfigTest

### Community 73 - "SourceRecognition::FinancialEmailFilterTest"
Cohesion: 0.40
Nodes (3): TestCase, SourceRecognition, SourceRecognition::FinancialEmailFilterTest

### Community 74 - "ExpenseTracker"
Cohesion: 0.50
Nodes (3): Application, ExpenseTracker, ExpenseTracker::Application

### Community 88 - "Application Brand Icon"
Cohesion: 1.00
Nodes (3): Application Brand Icon, Application Icon (PNG Raster), Application Icon (SVG Vector)

### Community 90 - "Alertas de gasto — UI/UX Design Specification"
Cohesion: 0.08
Nodes (24): 0. Findings from the current app (decisions made from architecture), 10. Testing checklist (mapped from the task), 11. Routes reference, 12. Implementation order (recommended), 1. Goal and scope, 2.1 `spending_alerts` table, 2.2 `alert_preferences` table (has_one on User), 2.3 Constants (single definition, in the service/model) (+16 more)

### Community 124 - "Category Management"
Cohesion: 0.67
Nodes (3): Category Form (Create/Edit), Category Management, Category Deletion: Reassign or Archive

### Community 142 - "@playwright/test"
Cohesion: 0.11
Nodes (10): { test, expect }, { test, expect }, { test, expect }, { test, expect }, { test, expect }, { test, expect }, { test, expect }, { test, expect } (+2 more)

### Community 143 - "Presupuesto por categoría — UI/UX Design Specification"
Cohesion: 0.11
Nodes (17): 10. Testing checklist (mapped from the task), 1. Goal, 2. Where it fits, 3. Domain surface (UI relies on, never reimplements), 4.1 Page header (reuse existing pattern), 4.2 Month navigation (matches dashboard `?month=` UX), 4.3 Summary strip (optional, restrained), 4.4 Budget cards (+9 more)

### Community 146 - "recurring_template_processor.rb"
Cohesion: 0.29
Nodes (7): call(), coerce_date(), failure(), normalize_amount(), period_range_for(), RecurringTemplateProcessor, RecurringTemplateProcessor::Result

### Community 177 - "Transfer"
Cohesion: 0.18
Nodes (5): Transfer, IntegrationTest, TransfersControllerTest, TestCase, TransferTest

### Community 182 - "ai_entry_turbo.spec.js"
Cohesion: 0.22
Nodes (4): FakeRecognition, PARSE_RESPONSE, { signUp }, { test, expect }

### Community 183 - "ApplicationRecord"
Cohesion: 0.40
Nodes (3): AlertPreference, ApplicationRecord, Base

### Community 185 - "ApplicationJob"
Cohesion: 0.29
Nodes (3): ApplicationJob, Base, GmailSetupSyncJob

### Community 186 - "Gmail::OauthClient"
Cohesion: 0.29
Nodes (6): Gmail, Gmail::OauthClient, Gmail::OauthClient::ConfigurationError, Gmail::OauthClient::Error, StandardError, Error

### Community 188 - "financial_setup_wizard.spec.js"
Cohesion: 0.38
Nodes (5): choose(), { signUp }, skipCash(), skipSteps(), { test, expect }

### Community 189 - "EncryptedSecret"
Cohesion: 0.60
Nodes (3): EncryptedSecret, encrypts_secret(), secret_encryptor()

## Knowledge Gaps
- **219 isolated node(s):** `$schema`, `plugin`, `FinancialSetupWizard::Step`, `FinancialSetups::Completer::Result`, `RecurringTemplateProcessor::Result` (+214 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 889 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **112 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ApplicationRecord` connect `ApplicationRecord` to `MoneySourceRecognitionIdentifier`, `CreditAccount`, `MoneySource`, `Gmail::ExpenseImporter`, `Budget`, `RecurringTemplate`, `Transfer`, `MoneySourceRecognition`, `Transaction`, `QaValidateDashboardReportsController`, `Category`, `SourceRecognition::DiscoveryService`, `GmailConnection`, `FinancialSetup`?**
  _High betweenness centrality (0.131) - this node is a cross-community bridge._
- **Why does `ApplicationController` connect `ApplicationController` to `GmailConnectionsController`, `ExpensesController`, `IncomesController`, `FinancialSetupsController`, `RecurringTemplateImporter`, `Budget`, `TransfersController`, `RecurringTemplatesController`, `MoneySourcesController`, `AlertsController`, `QaValidateDashboardReportsController`, `Category`, `RecurringTemplateActions`?**
  _High betweenness centrality (0.077) - this node is a cross-community bridge._
- **Why does `Category` connect `Category` to `ExpensesController`, `IncomesController`, `ExpenseParser`, `FinancialSetupsController`, `RecurringTemplateImporter`, `Budget`, `RecurringTemplatesController`, `Expenses::Create`, `ApplicationRecord`, `RecurringTemplateActions`?**
  _High betweenness centrality (0.071) - this node is a cross-community bridge._
- **What connects `$schema`, `plugin`, `FinancialSetupWizard::Step` to the rest of the system?**
  _219 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `ExpensesController` be split into smaller, more focused modules?**
  _Cohesion score 0.0545790934320074 - nodes in this community are weakly interconnected._
- **Should `ExpenseParser` be split into smaller, more focused modules?**
  _Cohesion score 0.07020408163265306 - nodes in this community are weakly interconnected._
- **Should `auth.js` be split into smaller, more focused modules?**
  _Cohesion score 0.14035087719298245 - nodes in this community are weakly interconnected._