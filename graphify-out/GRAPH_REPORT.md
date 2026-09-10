# Graph Report - expense-tracker  (2026-09-10)

## Corpus Check
- 335 files · ~170,905 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 2311 nodes · 2922 edges · 266 communities (89 shown, 150 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 68 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `98e5aa60`
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
- ImportPipeline
- Gmail::ExpenseImporter
- application.js
- Ai::TransactionExtractor
- Bulk Update Expense Category and Money Source
- ApplicationHelper
- RecurringTemplate
- SourceRecognition::Matcher
- ExpensePlayground::FileProcessor
- MoneySourcesController
- Gmail::QueryBuilder
- Reglas automáticas — UI/UX Design Spec
- Category Data Model
- Category
- ExpensePlaygroundController
- FinancialSetups::Completer
- SourceRecognition::DiscoveryService
- Speech-to-Text (local, faster-whisper)
- RecurringTemplateActions
- FinancialSetup
- FinancialSetups::StepPresenter
- Gmail::Client
- TransactionRules::Applicator
- ExpensePlayground::ProcessingService
- Gmail::SetupScanServiceTest::FakeClient
- IncomesController
- Detailed relationships
- CreditAccount
- createCategory
- Expense Model
- Hybrid Financial Setup Wizard
- ApplicationController
- SpeechToText::WhisperTest
- ExpensesHelper
- SpendingAlertService
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
- recurring_template_processor.rb
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
- .execute
- SpeechToText::Whisper
- RemapLegacyLinksToTransactions
- SpeechToText
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
- TransactionRulesController
- RecurringTemplatesController
- BudgetsController
- AlertsController
- BudgetsHelper
- alerts.spec.js
- budgets.spec.js
- Transfer
- MoneySourceRecognitionIdentifier
- TransactionRule
- graphify.js
- AGENTS.md
- ai_entry_turbo.spec.js
- ApplicationRecord
- Transaction
- TransactionRules::SuggestionService
- TransactionRulesHelper
- ExpensePlayground::Evaluation
- financial_setup_wizard.spec.js
- Ai::ImageExpenseExtractor
- money_source_tags.spec.js
- GmailSetupSyncJobTest
- AddSetupSuggestionsToGmailConnections
- AlertsHelper
- CreateSpendingAlerts
- opencode.json
- ExpenseCandidate
- CreateAlertPreferences
- CascadeDeleteProcessedEmailsOnExpense
- CreateBudgets
- AlertSettingsControllerTest
- AlertsControllerTest
- BudgetsControllerTest
- AlertPreferenceTest
- SpendingAlertTest
- MoneySourceRecognition
- Budget
- .stub_method
- MonthlyReportsController
- credit_cards_and_loans.spec.js
- BudgetTest
- .call
- transaction_rules_extended.spec.js
- ExpensePlayground::Input
- .call
- SpeechToText::Result
- CreateTransactionRules
- AddAppliedRuleIdsToTransactions
- AddTagsToTransactions
- AllowNullCategoryOnTransactions
- ai_entry_rules.spec.js
- transaction_rules_focused.spec.js
- Ocr::LocalReader
- ExpensePlayground::DuplicateDetectorTest
- AddDismissedRuleSuggestionsToUsers
- SourceRecognition::Catalog
- FinancialCatalogSeeder
- DashboardControllerTest
- AppHealthTest
- Gmail::SetupScanService
- .call
- .fold
- SpendingAlert
- GmailSyncJob
- ApplicationJob
- expense_playground.spec.js
- ExpensePlayground
- CreateExpensePlaygroundRuns
- expense_playground_file_import.spec.js
- ExpensePlayground::ProcessingServiceTest
- ExpensePlaygroundRunTest
- ExpensePlaygroundControllerTest
- Gmail::OauthClient
- GmailConnection
- Ocr
- Expenses::CreateTest
- TransactionRuleTest
- ExpensePlaygroundRun
- ExpensePlayground::EvaluationTest
- Expenses
- EncryptedSecret
- CreateActivityClassifications
- ActivityClassificationTest
- SpendingAlertServiceTest
- ActiveSupport::TestCase
- MonthlyIncomesController
- processing_service.rb
- whisper_transcribe.py
- speech_to_text_test.rb
- whisper.rb
- ExpenseCandidateTest
- SpeechToText
- ExpensePlaygroundAudioControllerTest
- ExpensePlayground::FileProcessorTest
- TransactionRulesControllerTest
- TransactionRulesFlowTest

## God Nodes (most connected - your core abstractions)
1. `Category` - 43 edges
2. `ExpensesController` - 35 edges
3. `@playwright/test` - 33 edges
4. `FinancialSetupsController` - 32 edges
5. `ExpenseParser` - 32 edges
6. `ExpensePlayground::FileProcessor` - 31 edges
7. `MoneySource` - 29 edges
8. `Ai::StatementExtractor` - 29 edges
9. `ExpensePlayground::Input` - 29 edges
10. `ApplicationHelper` - 25 edges

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

## Communities (266 total, 150 thin omitted)

### Community 1 - "ExpensesController"
Cohesion: 0.05
Nodes (9): ExpensesController, Expense, BudgetsFlowTest, IntegrationTest, CategorySpendTest, TestCase, TestCase, TransactionRules (+1 more)

### Community 2 - "ExpenseParser"
Cohesion: 0.06
Nodes (10): call(), ExpenseParser, ExpenseParser::AIError, ExpenseParser::Resolution, StandardError, ParsedExpense, ExpenseParserTest, ExpenseParserTest::FakeHttp (+2 more)

### Community 3 - "auth.js"
Cohesion: 0.11
Nodes (16): { signUp }, { test, expect }, { signUp, createCategory }, { test, expect }, { signUp, signIn }, { test, expect }, { signUp, createCategory }, { test, expect } (+8 more)

### Community 4 - "MoneySource"
Cohesion: 0.06
Nodes (6): MoneySource, MoneySources, MoneySources::Detector, MoneySources, MoneySources::Match, SanitizeMoneySourceIdentifiersToLastFour

### Community 5 - "Gmail::ExpenseImporterTest"
Cohesion: 0.10
Nodes (9): EmailTransactionDetector, EmailTransactionDetector::Result, EmailTransactionDetectorTest, TestCase, Gmail, Gmail::ExpenseImporterTest, Gmail::ExpenseImporterTest::FakeDetector, Gmail::ExpenseImporterTest::FakeExtractor (+1 more)

### Community 6 - "Category Management UI/UX Spec"
Cohesion: 0.06
Nodes (38): Add Expense Form Design Spec, Bootstrap 5 Components, Category Dropdown, Centered Modal or Card Layout, Bootstrap 5 Color Palette, Form Validation States, Category Management UI/UX Spec, Custom Category Grouping (+30 more)

### Community 7 - "Ai::StatementExtractor"
Cohesion: 0.10
Nodes (8): Ai, Ai::StatementExtractor, Ai::StatementExtractor::ExtractionError, parse(), StandardError, Ai, Ai::StatementExtractorTest, TestCase

### Community 9 - "ImportPipeline"
Cohesion: 0.09
Nodes (7): ImportPipeline, ImportPipeline::Result, ParsedStatement, FinancialSetupsControllerTest, IntegrationTest, TestCase, StatementDuplicateDetectorTest

### Community 10 - "Gmail::ExpenseImporter"
Cohesion: 0.05
Nodes (16): ProcessedEmail, Gmail, Gmail::ExpenseImporter, Gmail::ExpenseImporter::Result, call(), Gmail, Gmail::SyncService, configure() (+8 more)

### Community 11 - "application.js"
Cohesion: 0.12
Nodes (26): bindAvailableCredit(), bindForm(), bindInput(), bindRecognition(), decimalParts(), formatCurrencyNumber(), formatInput(), formatValue() (+18 more)

### Community 12 - "Ai::TransactionExtractor"
Cohesion: 0.11
Nodes (8): Ai, Ai::TransactionExtractor, Ai::TransactionExtractor::ExtractionError, parse(), StandardError, Ai, Ai::TransactionExtractorTest, TestCase

### Community 13 - "Bulk Update Expense Category and Money Source"
Cohesion: 0.08
Nodes (27): Bulk Bar (Expenses index), Bulk Update Expense Category and Money Source, category_badge Helper, ExpensesController#bulk_update, MoneySource.active Scope, MoneySource#display_name, Recurring Transactions UI (Income & Expense), Monthly Recurring Expenses UI (+19 more)

### Community 16 - "SourceRecognition::Matcher"
Cohesion: 0.13
Nodes (6): call(), SourceRecognition, SourceRecognition::Matcher, TestCase, SourceRecognition, SourceRecognition::MatcherTest

### Community 17 - "ExpensePlayground::FileProcessor"
Cohesion: 0.08
Nodes (6): ExpensePlayground, ExpensePlayground::DuplicateDetector, call(), ExpensePlayground, ExpensePlayground::FileProcessor, ExpensePlayground::FileProcessor::Result

### Community 18 - "MoneySourcesController"
Cohesion: 0.05
Nodes (11): MoneySourcesController, MoneyFormat, call(), SourceRecognition, SourceRecognition::ApplyToSearchConfig, SourceRecognition, SourceRecognition::SuggestionEngine, SourceRecognition::SuggestionEngine::Suggestion (+3 more)

### Community 19 - "Gmail::QueryBuilder"
Cohesion: 0.11
Nodes (6): build(), Gmail, Gmail::QueryBuilder, Gmail, Gmail::QueryBuilderTest, TestCase

### Community 20 - "Reglas automáticas — UI/UX Design Spec"
Cohesion: 0.10
Nodes (19): 1. Placement & navigation, 2. Data model (for design reference, implemented by Developer), 3. Main page — Rules index, 4. New / Edit rule — builder, 5. Interactions, 6. States, 7. Responsive behavior, 8. Accessibility (+11 more)

### Community 21 - "Category Data Model"
Cohesion: 0.16
Nodes (18): Category Data Model, Expense Data Model, Dashboard Example, Category Breakdown Chart, Recent Transactions List, Dashboard Stat Cards, Add Expense Form Design, Expense Entry Form (+10 more)

### Community 22 - "Category"
Cohesion: 0.05
Nodes (7): CategoriesController, ImportsController, ActivityClassification, Category, Expenses, Expenses::ActivityClassifier, RecurringTemplateImporter

### Community 24 - "FinancialSetups::Completer"
Cohesion: 0.18
Nodes (3): FinancialSetups, FinancialSetups::Completer, FinancialSetups::Completer::Result

### Community 25 - "SourceRecognition::DiscoveryService"
Cohesion: 0.18
Nodes (4): call(), SourceRecognition, SourceRecognition::DiscoveryService, SourceRecognition::DiscoveryService::Result

### Community 26 - "Speech-to-Text (local, faster-whisper)"
Cohesion: 0.08
Nodes (26): ActionCable Configuration, PostgreSQL Database Configuration, Gmail Integration I18n Keys (English), Solid Queue Configuration, Recurring Tasks Configuration, ActiveStorage Configuration, Colombian Financial Institutions Catalog, Financial Email Keywords Dictionary (+18 more)

### Community 30 - "Gmail::Client"
Cohesion: 0.19
Nodes (4): Gmail, Gmail::Client, Gmail::Client::Error, StandardError

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
Cohesion: 0.13
Nodes (11): { signUp, createCategory }, { test, expect }, { signUp, createCategory }, { test, expect }, createCategory(), createExpense(), createSuggestionData(), { signUp, createCategory } (+3 more)

### Community 38 - "Expense Model"
Cohesion: 0.24
Nodes (12): Categories I18n Keys (English), Expenses I18n Keys (English), Categories I18n Keys (Spanish), Expenses I18n Keys (Spanish), Category Model (Nested Hierarchy), Dashboard (Summary Cards, Quick Add, Recent Expenses), Devise Authentication Rationale, Expense Model (+4 more)

### Community 39 - "Hybrid Financial Setup Wizard"
Cohesion: 0.17
Nodes (12): Money Source Form, Hybrid Financial Setup Wizard, Setup Complete State, Duplicate Card Handling, Extraction Review Step, Statement File Upload, Final Review Step, Manual Account Entry (+4 more)

### Community 40 - "ApplicationController"
Cohesion: 0.17
Nodes (4): AlertSettingsController, ApplicationController, Base, MonthlyExpensesController

### Community 41 - "SpeechToText::WhisperTest"
Cohesion: 0.33
Nodes (4): TestCase, SpeechToText, SpeechToText::WhisperTest, SpeechToText::WhisperTest::FakeStatus

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

### Community 61 - "recurring_template_processor.rb"
Cohesion: 0.29
Nodes (7): call(), coerce_date(), failure(), normalize_amount(), period_range_for(), RecurringTemplateProcessor, RecurringTemplateProcessor::Result

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

### Community 76 - ".execute"
Cohesion: 0.15
Nodes (3): AddCategoryFormFields, BackfillTransactionsAndTemplates, NormalizeTransactionSigns

### Community 79 - "SpeechToText"
Cohesion: 0.19
Nodes (8): Error, StandardError, SpeechToText, SpeechToText::Error, SpeechToText::PreprocessingError, SpeechToText::ProviderUnavailableError, SpeechToText::TranscriptionError, SpeechToText::UnsupportedFormatError

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

### Community 177 - "Transfer"
Cohesion: 0.18
Nodes (5): Transfer, IntegrationTest, TransfersControllerTest, TestCase, TransferTest

### Community 182 - "ai_entry_turbo.spec.js"
Cohesion: 0.22
Nodes (4): FakeRecognition, PARSE_RESPONSE, { signUp }, { test, expect }

### Community 183 - "ApplicationRecord"
Cohesion: 0.22
Nodes (4): AlertPreference, ApplicationRecord, Base, User

### Community 188 - "financial_setup_wizard.spec.js"
Cohesion: 0.38
Nodes (5): choose(), { signUp }, skipCash(), skipSteps(), { test, expect }

### Community 189 - "Ai::ImageExpenseExtractor"
Cohesion: 0.10
Nodes (7): Ai, Ai::ImageExpenseExtractor, Ai::ImageExpenseExtractor::ExtractionError, StandardError, Ai, Ai::ImageExpenseExtractorTest, TestCase

### Community 207 - ".stub_method"
Cohesion: 0.17
Nodes (6): ExpensePlayground, ExpensePlayground::MoneySourceDetectionTest, TestCase, ExpensePlayground, ExpensePlayground::ProcessingServiceAudioTest, TestCase

### Community 211 - ".call"
Cohesion: 0.23
Nodes (4): Expenses, Expenses::Create, Expenses::Create::Invalid, StandardError

### Community 213 - "ExpensePlayground::Input"
Cohesion: 0.05
Nodes (13): build(), ExpensePlayground, ExpensePlayground::Adapters, ExpensePlayground::Adapters::AudioAdapter, ExpensePlayground::Adapters::Base, ExpensePlayground::Adapters::FileAdapter, ExpensePlayground::Adapters::ImageAdapter, ExpensePlayground::Adapters::TextAdapter (+5 more)

### Community 214 - ".call"
Cohesion: 0.29
Nodes (4): bin(), call(), SpeechToText, SpeechToText::AudioPreprocessor

### Community 223 - "ExpensePlayground::DuplicateDetectorTest"
Cohesion: 0.33
Nodes (3): ExpensePlayground, ExpensePlayground::DuplicateDetectorTest, TestCase

### Community 225 - "SourceRecognition::Catalog"
Cohesion: 0.22
Nodes (3): FinancialInstitution, SourceRecognition, SourceRecognition::Catalog

### Community 226 - "FinancialCatalogSeeder"
Cohesion: 0.18
Nodes (3): FinancialKeyword, FinancialSubjectPattern, FinancialCatalogSeeder

### Community 229 - "Gmail::SetupScanService"
Cohesion: 0.23
Nodes (3): call(), Gmail, Gmail::SetupScanService

### Community 230 - ".call"
Cohesion: 0.24
Nodes (4): call(), SourceRecognition, SourceRecognition::FinancialEmailFilter, SourceRecognition::FinancialEmailFilter::Result

### Community 234 - "ApplicationJob"
Cohesion: 0.29
Nodes (3): ApplicationJob, Base, GmailSetupSyncJob

### Community 236 - "ExpensePlayground"
Cohesion: 0.50
Nodes (3): ExpensePlayground, ExpensePlayground::AdaptersTest, TestCase

### Community 239 - "ExpensePlayground::ProcessingServiceTest"
Cohesion: 0.33
Nodes (3): ExpensePlayground, ExpensePlayground::ProcessingServiceTest, TestCase

### Community 242 - "Gmail::OauthClient"
Cohesion: 0.29
Nodes (6): Gmail, Gmail::OauthClient, Gmail::OauthClient::ConfigurationError, Gmail::OauthClient::Error, Error, StandardError

### Community 244 - "Ocr"
Cohesion: 0.50
Nodes (3): Ocr, Ocr::LocalReaderTest, TestCase

### Community 245 - "Expenses::CreateTest"
Cohesion: 0.40
Nodes (3): Expenses, Expenses::CreateTest, TestCase

### Community 248 - "ExpensePlayground::EvaluationTest"
Cohesion: 0.40
Nodes (3): ExpensePlayground, ExpensePlayground::EvaluationTest, TestCase

### Community 249 - "Expenses"
Cohesion: 0.50
Nodes (3): Expenses, Expenses::ActivityClassifierTest, TestCase

### Community 250 - "EncryptedSecret"
Cohesion: 0.60
Nodes (3): EncryptedSecret, encrypts_secret(), secret_encryptor()

### Community 256 - "processing_service.rb"
Cohesion: 0.40
Nodes (3): call(), ExpensePlayground, ExpensePlayground::ProcessingService::Result

### Community 257 - "whisper_transcribe.py"
Cohesion: 0.60
Nodes (4): fail(), main(), parse_args(), Local Speech-to-Text with faster-whisper. Invoked by SpeechToText::Whisper.…

### Community 258 - "speech_to_text_test.rb"
Cohesion: 0.40
Nodes (3): TestCase, SpeechToText::FutureTestProvider, SpeechToTextTest

### Community 262 - "SpeechToText"
Cohesion: 0.50
Nodes (3): TestCase, SpeechToText, SpeechToText::AudioPreprocessorTest

### Community 266 - "ExpensePlayground::FileProcessorTest"
Cohesion: 0.40
Nodes (3): ExpensePlayground, ExpensePlayground::FileProcessorTest, TestCase

## Knowledge Gaps
- **261 isolated node(s):** `$schema`, `plugin`, `ExpensePlayground::FileProcessor::Result`, `FinancialSetupWizard::Step`, `FinancialSetups::Completer::Result` (+256 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1108 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **150 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ApplicationRecord` connect `ApplicationRecord` to `SourceRecognition::Catalog`, `FinancialCatalogSeeder`, `CreditAccount`, `MoneySource`, `SpendingAlert`, `Gmail::ExpenseImporter`, `MoneySourceRecognition`, `Budget`, `RecurringTemplate`, `Transfer`, `MoneySourceRecognitionIdentifier`, `GmailConnection`, `TransactionRule`, `Category`, `ExpensePlaygroundRun`, `Transaction`, `FinancialSetup`?**
  _High betweenness centrality (0.149) - this node is a cross-community bridge._
- **Why does `Category` connect `Category` to `ExpensePlayground::ProcessingService`, `ExpensesController`, `IncomesController`, `TransactionRules::SuggestionService`, `MoneySource`, `FinancialSetupsController`, `TransactionRulesController`, `RecurringTemplatesController`, `BudgetsController`, `ExpensePlayground::FileProcessor`, `.call`, `ExpensePlaygroundController`, `ApplicationRecord`, `RecurringTemplateActions`?**
  _High betweenness centrality (0.124) - this node is a cross-community bridge._
- **Why does `ApplicationController` connect `ApplicationController` to `GmailConnectionsController`, `ExpensesController`, `IncomesController`, `FinancialSetupsController`, `MonthlyReportsController`, `RecurringTemplatesController`, `BudgetsController`, `AlertsController`, `MoneySourcesController`, `TransactionRulesController`, `Category`, `ExpensePlaygroundController`, `TransfersController`, `MonthlyIncomesController`?**
  _High betweenness centrality (0.060) - this node is a cross-community bridge._
- **What connects `$schema`, `plugin`, `ExpensePlayground::FileProcessor::Result` to the rest of the system?**
  _261 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `ExpensesController` be split into smaller, more focused modules?**
  _Cohesion score 0.052244897959183675 - nodes in this community are weakly interconnected._
- **Should `ExpenseParser` be split into smaller, more focused modules?**
  _Cohesion score 0.06313497822931785 - nodes in this community are weakly interconnected._
- **Should `auth.js` be split into smaller, more focused modules?**
  _Cohesion score 0.11231884057971014 - nodes in this community are weakly interconnected._