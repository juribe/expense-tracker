# Graph Report - expense-tracker  (2026-10-05)

## Corpus Check
- 700 files · ~360,794 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 5062 nodes · 6741 edges · 573 communities (257 shown, 279 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 199 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `aa336c53`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- GmailConnectionsController
- .render
- ExpenseResolver::MoneySourceResult
- auth.js
- MoneySource
- Gmail::ExpenseImporterTest
- Category Management UI/UX Spec
- Ai::StatementExtractor
- FinancialSetupsController
- ParsedStatement
- Gmail::SyncServiceTest
- application.js
- Ai::TransactionExtractor
- Bulk Update Expense Category and Money Source
- ApplicationHelper
- RecurringTemplate
- SourceRecognition::Matcher
- ExpenseResolver::Amounts::SumValidator
- reconciliation.js
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
- ReconciliationsController
- analyze_benchmark_500.py
- Gmail::SetupScanServiceTest::FakeClient
- ExpenseResolver::CandidateDetector
- Detailed relationships
- SourceRecognition::Catalog
- pickCategory
- Expense Model
- Hybrid Financial Setup Wizard
- MoneySourceRecognitionIdentifier
- Ai::Metrics
- ExpensesHelper
- SpendingAlertService
- Credit Cards and Loans
- Support Monthly Income and Payments
- financial_setup_wizard.rb
- Source Recognition Implementation Guide
- ExpensePlayground::Evaluations::Dataset
- Money Sources Definition
- Expense Views Table
- Implementation
- MigrateTagsToRecognitionIdentifiers
- Category Management Design
- package.json
- ImportPipeline
- ExpenseDashboardService
- Bulk Update Expense Category and Money Source
- 400 Bad Request Error Page
- ImportPipelineTest
- SourceRecognition::DiscoveryServiceTest
- Ai::Provider
- Devise Authentication Forms
- WhatsappMessageEvent
- oauth_client.rb
- WhatsappPayload
- Users::RegistrationsController
- DashboardHelper
- MoneySource (Accounts, Credit Cards, Loans)
- ExpensesControllerTest
- ConnectionMonitor
- MoneySourcesController
- SourceRecognition::ApplyToSearchConfigTest
- SourceRecognition::FinancialEmailFilterTest
- ExpenseTracker
- AddDeviseToUsers
- .execute
- SpeechToText::Whisper
- Ai::CategoryClassifier
- SpeechToText
- RemoveFrequencyFromTransactions
- DropMonthlyExpenseAndRecurringTransactionTables
- Ai::Tasks::Base
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
- .call
- User
- ExpenseResolver::Categories::Service
- Statements::ReviewBuilder
- BudgetsHelper
- alerts.spec.js
- CategoryPickerField
- Transfer
- Expenses::Inputs::File
- BudgetsController
- graphify.js
- AGENTS.md
- ai_entry_turbo.spec.js
- .answer
- FinancialCatalogSeeder
- TransactionRules::SuggestionService
- TransactionRulesHelper
- ExpensePlayground::Evaluation
- financial_setup_wizard.spec.js
- Ai::ImageExpenseExtractor
- Expenses::BulkCreate
- GmailSetupSyncJobTest
- AddSetupSuggestionsToGmailConnections
- AlertsHelper
- CreateSpendingAlerts
- cloudflare
- ExpenseCandidate
- CreateAlertPreferences
- CascadeDeleteProcessedEmailsOnExpense
- CreateBudgets
- AlertSettingsControllerTest
- AlertsControllerTest
- BudgetsControllerTest
- AlertPreferenceTest
- SpendingAlertTest
- 3. Full acceptance criteria (must all hold after implementation)
- ExpenseResolver::Service
- ExpensePlayground::DuplicateDetector
- Expenses::ValueParsing
- IncomesController
- Rails Standards
- Ai::Configuration
- transaction_rules_extended.spec.js
- inputs/base.rb
- .call
- Ai::Tasks::ExpenseExtraction
- CreateTransactionRules
- AddAppliedRuleIdsToTransactions
- AddTagsToTransactions
- AllowNullCategoryOnTransactions
- expense_playground_evaluation.spec.js
- transaction_rules_focused.spec.js
- Gmail::ExpenseImporter
- Gmail::SyncService
- AddDismissedRuleSuggestionsToUsers
- Webhooks::WhatsappController
- Ai::Tasks::SpreadsheetMapping
- DashboardControllerTest
- AppHealthTest
- Expenses::Inputs::Audio
- PendingWhatsappConnection
- Expenses::Processors::Image::VisionCandidateBuilder
- RecurringTemplateImporter
- GmailSyncJob
- TransactionRulesController
- Expenses::Search
- Gmail::SetupScanService
- CreateExpensePlaygroundRuns
- expense_playground_file_import.spec.js
- TransactionRule
- ExpensePlaygroundRunTest
- ExpensePlaygroundEvaluationsDatasetTest
- Gmail::OauthClient
- GmailConnection
- Ocr
- Users::PasswordsController
- Categories::Decision
- ExpensePlayground::Evaluations::Comparator
- .normalize_name
- Expenses
- EncryptedSecret
- CreateActivityClassifications
- ActivityClassificationTest
- Expenses::FileImport::CandidateBuilder
- Ai::Tasks::CategoryClassification
- Step-by-Step Workflow (DO NOT SKIP STEPS)
- FinancialSummaryService
- whisper_transcribe.py
- speech_to_text_test.rb
- ExpenseResolver::DescriptionResult
- Reconciliation::Calculator
- ExpenseClarification
- SpeechToText
- Expenses::ConfidenceCalculator
- Expense
- Ai::Providers::OpenRouter
- ExpensePlayground::Evaluations::Metrics
- ExpensePlayground::Evaluations::CaseProcessor
- Ai::Providers::FlexAi
- Ai::Providers::Mistral
- Expenses::Processors::Audio
- .fold
- Expenses::Inputs::DataUri
- Expenses::Inputs::Rules::Image
- EvaluationRun
- Expenses::InputsTest
- Reports::Period
- SpeechToText::WhisperTest
- EvaluationCase
- Ai::Pricing
- Expenses::Processors::Base
- FinancialSetupsControllerTest
- .call
- Expenses::RowResolver
- Ai
- Ai
- whatsapp_business_tools
- CreateAiRequests
- CreateSpreadsheetFormatMappings
- MoneySources::Detector
- WillPaginate::ActionView::BootstrapLinkRenderer
- Ai::Tasks::CategorySuggestion
- ExpenseResolver::AmountResult
- financial_chat.js
- .success?
- AiRequest
- Payments::BalanceEffect
- TransactionRules::SuggestionServiceTest
- ExpensePlayground::Evaluations::ResultBuilder
- Ai::Execution
- Expenses::Inputs::TextImage
- RSpec Standards
- PaymentsController
- ExpenseCandidatesController
- whisper.rb
- CreateEvaluationRuns
- CreateEvaluationCases
- AddAttemptsToEvaluationCases
- AddInputOutputCostToEvaluationCases
- AiExecutionTest
- RemapLegacyLinksToTransactions
- ExpenseResolver::CategoryResult
- StatementImportsController
- Reports::Transfers
- Statements::Confirmation
- MigrateMoneySourceIdentifiersToTags
- StatementDuplicateDetector
- Ruby Standards
- Expenses::Inputs::Text
- .call
- Expenses::Inputs
- CreditAccount
- questions.rb
- Expenses::FileImport::Readers::Extraction
- Ai::RouterTest::FakeTask
- Ai::Tasks::ConversationExpenseParsing
- WhatsappPayload::Message
- Expense Tracker Design System
- Expenses
- TransfersController
- Expenses::FileImport::Pipeline
- .call
- SpeechToText::Result
- FinancialChatChannel
- FinancialAnalysisService
- .call
- parser_test.rb
- ExpenseCandidates::BulkDiscard
- BulletIntegrationHook
- ExpenseResolver::DateResult
- WebHookHandler::WhatsappService
- MoneySources::Match
- Project Context
- ExpensePlayground::DuplicateDetectorTest
- Expenses::CandidateDeduplicator
- ApplicationJob
- ExpenseResolver
- ServiceResultTest
- Transaction
- Budget
- .call
- Expenses::MoneySourceDetectionTest
- ExpenseResolver
- ExpenseResolverHeuristicResolverTest
- .refresh!
- ExpensePlayground::EvaluationTest
- Expenses::FileImport::Enrichers::MoneySource
- ExpenseResolver
- Expenses::Result
- Ai::ConfigurationTest
- Expenses::FileImport::ImportContext
- Categories
- Expenses::FileProcessorTest
- Expenses::BulkDestroy
- ExpenseResolver
- CreateExpenseCandidates
- Expenses::Processors::Image
- Payment
- ReconciliationSnapshot
- Expenses::Clarification::Resolver
- AddCategorySuggestionToExpenseCandidates
- Expenses::SearchTest
- Expenses::Processors::Text
- Expenses::Inputs::Image
- .call
- .create
- ExpenseDecorator
- AddCandidatesToExpensePlaygroundRuns
- AddPromptAndOutputToAiRequests
- Expenses::FileImport::Enrichers::Confidence
- recurring_template_processor.rb
- ApplicationController
- ApplicationRecord
- Expenses::BulkUpdate
- SpendingAlert
- FinancialChatMarkdownRenderer
- FinancialChatMessage
- Expenses
- SanitizeMoneySourceIdentifiersToLastFour
- Expenses::Processors::Recording
- Expenses::FileImport::Readers::Csv
- AddWhatsappNumberToUsers
- MoneySources::BalanceSyncTest
- WhatsappWebhookControllerTest
- SourceRecognition::SuggestionEngine
- Expenses
- CategoryOptionListTest
- .stub_method
- ai_entry_rules.spec.js
- file_import/result.rb
- Reports::Insights
- .call
- Expenses::FileImport::TabularParser
- EmailTransactionDetectorTest
- .process_file
- Ocr::LocalReader
- Ai::Tasks::ClarificationResolution
- RecurringTemplatesController
- Ai
- ExpenseResolverServiceTest
- Reports::SpendingTrend
- Whatsapp::ConnectServiceTest
- garbage_filter.rb
- WhatsappSettingsControllerTest
- PendingWhatsappConnectionTest
- WhatsappConnectionTest
- WhatsappIdentityTest
- Statements::Summary
- AddSubKindToMoneySources
- ExpenseResolver::Serializer
- Whatsapp::MediaFetcherTest
- ExpensePlaygroundRun
- MoneySourceCapabilitiesTest
- Whatsapp::ReplySender
- Expenses::FileImport::Readers::Base
- Reports::MoneySources
- Statements::Document
- IncomesControllerTest
- RecurringTemplatesControllerTest
- AddPendingCategoryNameToExpenseClarifications
- ClarificationSessionsGroupManyCandidates
- payments.js
- credit_cards_and_loans.spec.js
- Expenses::Input
- .call
- ExpensePlaygroundEvaluationCaseJobTest
- Ai::Providers
- SidebarIndexesBulletTest
- ExpensePlayground::Evaluations::Runner
- Whatsapp
- Reports::Base
- CategoriesClosestResolverTest
- CreateExpenseClarifications
- CreateWhatsappInboundMessages
- Expenses::CandidateDeduplicatorTest
- ApplicationCable::Connection
- Expenses::BulkDestroyTest
- Expenses::FileImport::Readers::Pdf
- AddCategoryFormFields
- ReconciliationsHelper
- Reports::Filter
- ReportsHelper
- AddCachedBalanceToMoneySources
- CreatePayments
- ExpensePlaygroundEvaluationsComparatorTest
- ExpenseCandidates::BulkConfirmTest
- ExpenseCandidates::BulkUpdateTest
- MonthlyExpensesControllerTest
- RecurringTemplateProcessorTest
- Expenses::BulkCreateTest
- Expenses::BulkUpdateTest
- ExpenseCandidatesControllerTest
- Expenses::ConfidenceCalculatorTest
- Expenses::RecurringAssignmentTest
- Expenses::AudioProcessorTest
- connection_test.rb
- Statements
- AlertsController
- Payments::RecurringLink
- BudgetTest
- Reports::Budgets
- ExpensePlaygroundEvaluationsMetricsTest
- Reports::CategorySpending
- ApplicationCable
- Reports::Loans
- Reports::Overview
- WhatsappIdentity
- NullifyProcessedEmailsOnExpenseDelete
- financial_chat_channel_test.rb
- FinancialChats
- StatementImportsControllerTest
- CompleterTest
- Expenses::Inputs::Rules::Audio
- Reports::Recurring
- Gmail::QueryBuilderTest
- CreateSolidCableTables
- CreateFinancialChats
- CreateFinancialChatMessages
- FinancialChatControllerTest
- FinancialSummaryControllerTest
- FinancialChatMessageTest
- FinancialChatTest
- AddAdjustmentTraceToMoneySources
- Expenses::Inputs::Rules::File
- .call
- Expenses::RecurringAssignment
- .write
- expense_importer.rb
- AddGmailDuplicateProtection
- Statements
- Statements
- Statements
- .call
- ExpensePlaygroundControllerTest
- AddOutstandingUsageReplayedToCreditAccounts
- .for_user
- Reconciliation::Invalidatable
- ExpenseCandidates::BulkConfirm
- ExpenseCandidates::BulkDiscardTest
- Reports::CreditCards
- ExpenseCandidates::BulkUpdate
- FinancialAnalysisServiceTest
- SourceRecognition::MatcherTest
- PaymentsControllerTest
- ActiveSupport::TestCase
- Expenses::ProcessorTest
- expense-bulk-selection.spec.js
- ReportsLoansTest
- ReportsCreditCardsTest
- ReportsInsightsTest
- .recurring_commitment_increase
- expense_playground.spec.js
- SpendingAlertServiceTest
- Reconciliation::StateTest
- Ai::ImageExpenseExtractorTest
- BalanceEffectTest
- ReportsBudgetsTest
- Expenses::RowResolverTest
- Reconciliation
- Payments::RecurringLinkTest
- Reports::InsightsController
- TransactionRuleTest
- Reports::TransactionsController
- ReportsCategorySpendingTest
- Whatsapp::ReplySenderTest
- CreateReconciliationTables
- ExpensePlaygroundEvaluationsResultBuilderTest
- .load_dashboard
- ReportsPagesTest
- ReconciliationsControllerTest
- thresholds.rb
- Reports::CategorySpendingController
- FinancialChatMarkdownRendererTest
- MoneySourcesDetectorTest
- Reports::CreditCardsController
- Reports::LoansController
- .index
- Expenses::CreateTest
- Expenses
- balance_sync.rb
- BudgetsFlowTest
- TransactionRulesFlowTest
- ChartkickAssetTest
- ReportsCssTest
- Expenses
- ReportsRecurringTest
- ExpenseCandidateTest
- Reports::RecurringController
- AddUnverifiedCountToReconciliationStates
- .render_csv
- extraction.rb
- Expenses
- ExpensePlayground

## God Nodes (most connected - your core abstractions)
1. `Category` - 78 edges
2. `Expense` - 40 edges
3. `ApplicationRecord` - 39 edges
4. `ExpenseCandidate` - 38 edges
5. `@playwright/test` - 36 edges
6. `FinancialSetupsController` - 32 edges
7. `MoneySource` - 32 edges
8. `ApplicationHelper` - 31 edges
9. `Ai::StatementExtractor` - 31 edges
10. `ApplicationController` - 30 edges

## Surprising Connections (you probably didn't know these)
- `call()` --calls--> `Statements::Document`  [EXTRACTED]
  test/services/statements/parser_test.rb → app/services/statements/document.rb
- `Source Recognition (Gmail-based Email Matching)` --references--> `Colombian Financial Institutions Catalog`  [INFERRED]
  EXPLORATION_SUMMARY.md → db/seed_data/financial_institutions.yml
- `Expense List & Filters Design` --semantically_similar_to--> `Expense Views Table Design`  [INFERRED] [semantically similar]
  designs/design_expense_list_filters.md → designs/design_expense_views_table.md
- `Expense List and Filters Design` --semantically_similar_to--> `Expense Views Table`  [INFERRED] [semantically similar]
  mockups/design_expense_list_filters.html → mockups/design_expense_views_table.html
- `Gmail Integration I18n Keys (English)` --implements--> `Source Recognition (Gmail-based Email Matching)`  [EXTRACTED]
  config/locales/en.yml → EXPLORATION_SUMMARY.md

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

## Communities (573 total, 279 thin omitted)

### Community 2 - "ExpenseResolver::MoneySourceResult"
Cohesion: 0.18
Nodes (3): ExpenseResolver, ExpenseResolver::MoneySourceResult, ExpenseResolver::MoneySourceResult::Result

### Community 3 - "auth.js"
Cohesion: 0.10
Nodes (16): { signUp }, { test, expect }, { signUp, signIn }, { test, expect }, { signUp, createCategory }, { test, expect }, { signUp, createCategory }, { test, expect } (+8 more)

### Community 5 - "Gmail::ExpenseImporterTest"
Cohesion: 0.16
Nodes (5): Gmail, Gmail::ExpenseImporterTest, Gmail::ExpenseImporterTest::FakeDetector, Gmail::ExpenseImporterTest::FakeExtractor, TestCase

### Community 6 - "Category Management UI/UX Spec"
Cohesion: 0.06
Nodes (38): Add Expense Form Design Spec, Bootstrap 5 Components, Category Dropdown, Centered Modal or Card Layout, Bootstrap 5 Color Palette, Form Validation States, Category Management UI/UX Spec, Custom Category Grouping (+30 more)

### Community 7 - "Ai::StatementExtractor"
Cohesion: 0.07
Nodes (12): Ai, Ai::StatementExtractor, Ai::StatementExtractor::ExtractionError, parse(), StandardError, Ai, Ai::Tasks, Ai::Tasks::StatementExtraction (+4 more)

### Community 9 - "ParsedStatement"
Cohesion: 0.21
Nodes (3): ParsedStatement, TestCase, StatementDuplicateDetectorTest

### Community 10 - "Gmail::SyncServiceTest"
Cohesion: 0.14
Nodes (6): configure(), Gmail, Gmail::SyncServiceTest, Gmail::SyncServiceTest::FakeClient, Gmail::SyncServiceTest::FakeExtractor, TestCase

### Community 11 - "application.js"
Cohesion: 0.07
Nodes (40): bindAll(), bindAvailableCredit(), bindCard(), bindForm(), bindInput(), bindRecognition(), CategoryPicker(), connectCard() (+32 more)

### Community 12 - "Ai::TransactionExtractor"
Cohesion: 0.09
Nodes (12): Ai, Ai::Tasks, Ai::Tasks::TransactionExtraction, Base, Ai, Ai::TransactionExtractor, Ai::TransactionExtractor::ExtractionError, parse() (+4 more)

### Community 13 - "Bulk Update Expense Category and Money Source"
Cohesion: 0.08
Nodes (27): Bulk Bar (Expenses index), Bulk Update Expense Category and Money Source, category_badge Helper, ExpensesController#bulk_update, MoneySource.active Scope, MoneySource#display_name, Recurring Transactions UI (Income & Expense), Monthly Recurring Expenses UI (+19 more)

### Community 16 - "SourceRecognition::Matcher"
Cohesion: 0.19
Nodes (3): call(), SourceRecognition, SourceRecognition::Matcher

### Community 17 - "ExpenseResolver::Amounts::SumValidator"
Cohesion: 0.10
Nodes (8): ExpenseResolver, ExpenseResolver::Amounts, ExpenseResolver::Amounts::SumValidator, ExpenseResolver::Amounts::SumValidator::Result, ExpenseResolver, ExpenseResolver::Amounts, ExpenseResolver::Amounts::SumValidatorTest, TestCase

### Community 18 - "reconciliation.js"
Cohesion: 0.16
Nodes (29): assignCreateUrl(), assignModal(), assignResultRow(), assignSearchUrl(), csrfToken(), differenceMagnitude(), emptyRow(), escapeHtml() (+21 more)

### Community 19 - "Gmail::QueryBuilder"
Cohesion: 0.15
Nodes (3): build(), Gmail, Gmail::QueryBuilder

### Community 20 - "Reglas automáticas — UI/UX Design Spec"
Cohesion: 0.10
Nodes (19): 1. Placement & navigation, 2. Data model (for design reference, implemented by Developer), 3. Main page — Rules index, 4. New / Edit rule — builder, 5. Interactions, 6. States, 7. Responsive behavior, 8. Accessibility (+11 more)

### Community 21 - "Category Data Model"
Cohesion: 0.16
Nodes (18): Category Data Model, Expense Data Model, Dashboard Example, Category Breakdown Chart, Recent Transactions List, Dashboard Stat Cards, Add Expense Form Design, Expense Entry Form (+10 more)

### Community 22 - "Category"
Cohesion: 0.06
Nodes (5): CategoriesController, Category, SplitComidaYRestaurantesCategories, CategoryPickerHelperTest, TestCase

### Community 24 - "FinancialSetups::Completer"
Cohesion: 0.17
Nodes (3): FinancialSetups, FinancialSetups::Completer, FinancialSetups::Completer::Result

### Community 25 - "SourceRecognition::DiscoveryService"
Cohesion: 0.18
Nodes (4): call(), SourceRecognition, SourceRecognition::DiscoveryService, SourceRecognition::DiscoveryService::Result

### Community 26 - "Speech-to-Text (local, faster-whisper)"
Cohesion: 0.08
Nodes (26): ActionCable Configuration, PostgreSQL Database Configuration, Gmail Integration I18n Keys (English), Solid Queue Configuration, Recurring Tasks Configuration, ActiveStorage Configuration, Colombian Financial Institutions Catalog, Financial Email Keywords Dictionary (+18 more)

### Community 27 - "RecurringTemplateActions"
Cohesion: 0.09
Nodes (3): RecurringTemplateActions, MonthlyExpensesController, MonthlyIncomesController

### Community 29 - "FinancialSetups::StepPresenter"
Cohesion: 0.10
Nodes (5): FinancialSetups, FinancialSetups::StepPresenter, FinancialSetups, FinancialSetups::StepPresenterTest, TestCase

### Community 30 - "Gmail::Client"
Cohesion: 0.19
Nodes (4): Gmail, Gmail::Client, Gmail::Client::Error, StandardError

### Community 31 - "ReconciliationsController"
Cohesion: 0.12
Nodes (5): ReconciliationsController, Reconciliation, Reconciliation::ExpenseSearch, Reconciliation, Reconciliation::MovementSearch

### Community 32 - "analyze_benchmark_500.py"
Cohesion: 0.25
Nodes (14): amounts_in(), date_class_in(), date_window(), E(), evaluate(), ground_truth(), item_keywords(), main() (+6 more)

### Community 33 - "Gmail::SetupScanServiceTest::FakeClient"
Cohesion: 0.18
Nodes (5): configure(), Gmail, Gmail::SetupScanServiceTest, Gmail::SetupScanServiceTest::FakeClient, TestCase

### Community 34 - "ExpenseResolver::CandidateDetector"
Cohesion: 0.14
Nodes (5): ExpenseResolver, ExpenseResolver::CandidateDetector, ExpenseResolver, ExpenseResolver::Text, ExpenseResolver::Text::Service

### Community 35 - "Detailed relationships"
Cohesion: 0.09
Nodes (22): 1. Models & their relationships, 2. Services & their relationships, 3. Key cross-cutting relationships, 4. Data-flow story, Association map, Category, CreditAccount, Detailed relationships (+14 more)

### Community 36 - "SourceRecognition::Catalog"
Cohesion: 0.22
Nodes (3): FinancialInstitution, SourceRecognition, SourceRecognition::Catalog

### Community 37 - "pickCategory"
Cohesion: 0.08
Nodes (27): { pickCategory }, { signUp, createCategory }, { test, expect }, createBudget(), createExpense(), { pickCategory }, { signUp, createCategory }, { test, expect } (+19 more)

### Community 38 - "Expense Model"
Cohesion: 0.24
Nodes (12): Categories I18n Keys (English), Expenses I18n Keys (English), Categories I18n Keys (Spanish), Expenses I18n Keys (Spanish), Category Model (Nested Hierarchy), Dashboard (Summary Cards, Quick Add, Recent Expenses), Devise Authentication Rationale, Expense Model (+4 more)

### Community 39 - "Hybrid Financial Setup Wizard"
Cohesion: 0.17
Nodes (12): Money Source Form, Hybrid Financial Setup Wizard, Setup Complete State, Duplicate Card Handling, Extraction Review Step, Statement File Upload, Final Review Step, Manual Account Entry (+4 more)

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

### Community 48 - "ExpensePlayground::Evaluations::Dataset"
Cohesion: 0.17
Nodes (6): ExpensePlayground, ExpensePlayground::Evaluations, ExpensePlayground::Evaluations::Dataset, ExpensePlayground::Evaluations::Dataset::Invalid, ExpensePlayground::Evaluations::Dataset::Row, StandardError

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

### Community 61 - "Ai::Provider"
Cohesion: 0.06
Nodes (15): Ai, Ai::Provider, Ai::Provider::Error, Ai::Provider::Response, StandardError, Ai, Ai::FakeStreamingHttp, Ai::FakeStreamingResponse (+7 more)

### Community 62 - "Devise Authentication Forms"
Cohesion: 0.33
Nodes (6): Authentication Flow, Devise Authentication Forms, Forgot Password Form, Reset Password Form, Sign In Form, Sign Up Form

### Community 64 - "oauth_client.rb"
Cohesion: 0.29
Nodes (9): authorize_url(), configured?(), exchange_code(), parse_token_response(), perform(), post_token(), raise_configuration_error!(), refresh() (+1 more)

### Community 65 - "WhatsappPayload"
Cohesion: 0.18
Nodes (5): WhatsappPayload, WhatsappPayload::Change, WhatsappPayload::Contact, WhatsappPayload::Entry, WhatsappPayload::Value

### Community 68 - "MoneySource (Accounts, Credit Cards, Loans)"
Cohesion: 0.40
Nodes (5): Money Sources I18n Keys (English), Wizard I18n Keys (English), MoneySource (Accounts, Credit Cards, Loans), Transfer Between Money Sources, Financial Setup Wizard

### Community 70 - "ConnectionMonitor"
Cohesion: 0.05
Nodes (13): close(), Connection, ConnectionMonitor, Consumer, createConsumer(), createWebSocketURL(), error(), log() (+5 more)

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
Cohesion: 0.16
Nodes (3): BackfillTransactionsAndTemplates, NormalizeTransactionSigns, AddExpensesCounterCacheToCategories

### Community 78 - "Ai::CategoryClassifier"
Cohesion: 0.13
Nodes (8): Ai, Ai::CategoryClassifier, Ai::CategoryClassifier::ExtractionError, parse(), StandardError, Ai, Ai::CategoryClassifierTest, TestCase

### Community 79 - "SpeechToText"
Cohesion: 0.19
Nodes (8): Error, StandardError, SpeechToText, SpeechToText::Error, SpeechToText::PreprocessingError, SpeechToText::ProviderUnavailableError, SpeechToText::TranscriptionError, SpeechToText::UnsupportedFormatError

### Community 82 - "Ai::Tasks::Base"
Cohesion: 0.17
Nodes (5): Ai, Ai::Tasks, Ai::Tasks::Base, Ai::Tasks::Base::InvalidResponse, StandardError

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
Cohesion: 0.08
Nodes (15): { defineConfig }, fs, path, rubyVersionFile, rvm, { test, expect }, { test, expect }, { test, expect } (+7 more)

### Community 143 - "Presupuesto por categoría — UI/UX Design Specification"
Cohesion: 0.11
Nodes (17): 10. Testing checklist (mapped from the task), 1. Goal, 2. Where it fits, 3. Domain surface (UI relies on, never reimplements), 4.1 Page header (reuse existing pattern), 4.2 Month navigation (matches dashboard `?month=` UX), 4.3 Summary strip (optional, restrained), 4.4 Budget cards (+9 more)

### Community 144 - ".call"
Cohesion: 0.24
Nodes (4): call(), SourceRecognition, SourceRecognition::FinancialEmailFilter, SourceRecognition::FinancialEmailFilter::Result

### Community 145 - "User"
Cohesion: 0.15
Nodes (5): User, WhatsappConnection, CreateWhatsappLinkingTables, CategoryOptionTest, TestCase

### Community 146 - "ExpenseResolver::Categories::Service"
Cohesion: 0.33
Nodes (4): ExpenseResolver, ExpenseResolver::Categories, ExpenseResolver::Categories::Service, ExpenseResolver::Categories::Service::Resolution

### Community 147 - "Statements::ReviewBuilder"
Cohesion: 0.14
Nodes (3): Statements, Statements::ReviewBuilder, Statements::ReviewBuilder::Review

### Community 149 - "alerts.spec.js"
Cohesion: 0.25
Nodes (4): createExpense(), { pickCategory }, { signUp, createCategory }, { test, expect }

### Community 150 - "CategoryPickerField"
Cohesion: 0.06
Nodes (4): CategoryPickerHelper, CategoryOption, CategoryOptionList, CategoryPickerField

### Community 177 - "Transfer"
Cohesion: 0.12
Nodes (7): Transfer, IntegrationTest, TransfersControllerTest, TestCase, TransferTest, TestCase, ReportsTransfersTest

### Community 178 - "Expenses::Inputs::File"
Cohesion: 0.22
Nodes (4): Expenses, Expenses::Inputs, Expenses::Inputs::File, Base

### Community 182 - "ai_entry_turbo.spec.js"
Cohesion: 0.22
Nodes (4): FakeRecognition, PARSE_RESPONSE, { signUp }, { test, expect }

### Community 184 - "FinancialCatalogSeeder"
Cohesion: 0.18
Nodes (3): FinancialKeyword, FinancialSubjectPattern, FinancialCatalogSeeder

### Community 188 - "financial_setup_wizard.spec.js"
Cohesion: 0.38
Nodes (5): choose(), { signUp }, skipCash(), skipSteps(), { test, expect }

### Community 189 - "Ai::ImageExpenseExtractor"
Cohesion: 0.12
Nodes (4): Ai, Ai::ImageExpenseExtractor, Ai::ImageExpenseExtractor::ExtractionError, StandardError

### Community 195 - "cloudflare"
Cohesion: 0.25
Nodes (7): enabled, type, url, mcp, cloudflare, plugin, $schema

### Community 205 - "3. Full acceptance criteria (must all hold after implementation)"
Cohesion: 0.07
Nodes (27): 1. Ground rules (must govern every decision), 2. Current architecture facts (verified — do not re-derive), 2. Tasks, 3.1 Regression checklist (how to verify each criterion), 3. Full acceptance criteria (must all hold after implementation), 4. Commit order, Ambiguous transfer, Complete extraction (+19 more)

### Community 208 - "Expenses::ValueParsing"
Cohesion: 0.19
Nodes (6): Expenses, Expenses::FileImport, Expenses::FileImport::Enrichers, Expenses::FileImport::Enrichers::Activity, Expenses, Expenses::ValueParsing

### Community 209 - "IncomesController"
Cohesion: 0.13
Nodes (4): IncomesController, Income, TestCase, ReportsOverviewTest

### Community 210 - "Rails Standards"
Cohesion: 0.08
Nodes (23): Action order, Associations, Authorization, Background Work, Real-Time, Concerns and Service Objects, Controllers, Controllers, Database, File layout (+15 more)

### Community 211 - "Ai::Configuration"
Cohesion: 0.06
Nodes (9): Ai, Ai, Ai::Configuration, Ai, Ai::Router, call(), ExpenseResolver, ExpenseResolver::ConfidenceGate (+1 more)

### Community 212 - "transaction_rules_extended.spec.js"
Cohesion: 0.40
Nodes (3): { pickCategory }, { signUp, createCategory }, { test, expect }

### Community 213 - "inputs/base.rb"
Cohesion: 0.22
Nodes (12): channel_errors(), errors(), Expenses, Expenses::Inputs, Expenses::Inputs::Base, metadata(), presence_errors(), symbolize() (+4 more)

### Community 214 - ".call"
Cohesion: 0.29
Nodes (4): bin(), call(), SpeechToText, SpeechToText::AudioPreprocessor

### Community 215 - "Ai::Tasks::ExpenseExtraction"
Cohesion: 0.24
Nodes (4): Ai, Ai::Tasks, Ai::Tasks::ExpenseExtraction, Base

### Community 220 - "expense_playground_evaluation.spec.js"
Cohesion: 0.28
Nodes (5): filterCases(), handleEvaluationRoute(), mockEvaluationApi(), { signUp }, { test, expect }

### Community 221 - "transaction_rules_focused.spec.js"
Cohesion: 0.33
Nodes (3): { pickCategory }, { signUp, createCategory }, { test, expect }

### Community 223 - "Gmail::SyncService"
Cohesion: 0.24
Nodes (3): call(), Gmail, Gmail::SyncService

### Community 225 - "Webhooks::WhatsappController"
Cohesion: 0.20
Nodes (4): Base, Webhooks, Webhooks::WhatsappController, WhatsappWebhookJob

### Community 226 - "Ai::Tasks::SpreadsheetMapping"
Cohesion: 0.22
Nodes (4): Ai, Ai::Tasks, Ai::Tasks::SpreadsheetMapping, Base

### Community 229 - "Expenses::Inputs::Audio"
Cohesion: 0.22
Nodes (4): Expenses, Expenses::Inputs, Expenses::Inputs::Audio, Base

### Community 231 - "Expenses::Processors::Image::VisionCandidateBuilder"
Cohesion: 0.15
Nodes (5): Expenses::Processors::Image, Expenses::Processors::Image::VisionCandidateBuilder, Expenses::Processors::Image, Expenses::Processors::Image::VisionExtraction, Expenses::Processors::Image::VisionExtraction::Result

### Community 236 - "Gmail::SetupScanService"
Cohesion: 0.23
Nodes (3): call(), Gmail, Gmail::SetupScanService

### Community 239 - "TransactionRule"
Cohesion: 0.11
Nodes (5): TransactionRule, TransactionRules, TransactionRules::Applicator, IntegrationTest, TransactionRulesControllerTest

### Community 242 - "Gmail::OauthClient"
Cohesion: 0.29
Nodes (6): Gmail, Gmail::OauthClient, Gmail::OauthClient::ConfigurationError, Gmail::OauthClient::Error, Error, StandardError

### Community 244 - "Ocr"
Cohesion: 0.50
Nodes (3): Ocr, Ocr::LocalReaderTest, TestCase

### Community 245 - "Users::PasswordsController"
Cohesion: 0.18
Nodes (5): Users::PasswordsController, PasswordsController, SystemTestCase, ApplicationSystemTestCase, ReconciliationAssignModalTest

### Community 246 - "Categories::Decision"
Cohesion: 0.22
Nodes (3): Categories, Categories::Decision, Categories::Decision::Result

### Community 247 - "ExpensePlayground::Evaluations::Comparator"
Cohesion: 0.25
Nodes (3): ExpensePlayground, ExpensePlayground::Evaluations, ExpensePlayground::Evaluations::Comparator

### Community 248 - ".normalize_name"
Cohesion: 0.11
Nodes (5): ActivityClassification, Categories, Categories::HeuristicResolver, Expenses, Expenses::ActivityClassifier

### Community 249 - "Expenses"
Cohesion: 0.50
Nodes (3): Expenses, Expenses::ActivityClassifierTest, TestCase

### Community 250 - "EncryptedSecret"
Cohesion: 0.60
Nodes (3): EncryptedSecret, encrypts_secret(), secret_encryptor()

### Community 253 - "Expenses::FileImport::CandidateBuilder"
Cohesion: 0.21
Nodes (3): Expenses, Expenses::FileImport, Expenses::FileImport::CandidateBuilder

### Community 254 - "Ai::Tasks::CategoryClassification"
Cohesion: 0.21
Nodes (4): Ai, Ai::Tasks, Ai::Tasks::CategoryClassification, Base

### Community 255 - "Step-by-Step Workflow (DO NOT SKIP STEPS)"
Cohesion: 0.08
Nodes (23): 1. Identify the change type:, 2. Review existing test coverage:, 3. State your plan explicitly:, 4. Get user confirmation:, Context & Standards References, Core Principle, Pre-Flight Checklist, Related Skills (+15 more)

### Community 256 - "FinancialSummaryService"
Cohesion: 0.15
Nodes (4): FinancialSummaryController, FinancialSummaryService, FinancialSummaryServiceTest, TestCase

### Community 257 - "whisper_transcribe.py"
Cohesion: 0.60
Nodes (4): fail(), main(), parse_args(), Local Speech-to-Text with faster-whisper. Invoked by SpeechToText::Whisper.…

### Community 258 - "speech_to_text_test.rb"
Cohesion: 0.40
Nodes (3): TestCase, SpeechToText::FutureTestProvider, SpeechToTextTest

### Community 259 - "ExpenseResolver::DescriptionResult"
Cohesion: 0.25
Nodes (3): ExpenseResolver, ExpenseResolver::DescriptionResult, ExpenseResolver::DescriptionResult::Result

### Community 260 - "Reconciliation::Calculator"
Cohesion: 0.18
Nodes (5): call(), reconcilable_balance(), Reconciliation, Reconciliation::Calculator, Reconciliation::Calculator::Result

### Community 262 - "SpeechToText"
Cohesion: 0.50
Nodes (3): TestCase, SpeechToText, SpeechToText::AudioPreprocessorTest

### Community 263 - "Expenses::ConfidenceCalculator"
Cohesion: 0.17
Nodes (3): Expenses, Expenses::ConfidenceCalculator, Expenses::ConfidenceCalculator::Result

### Community 264 - "Expense"
Cohesion: 0.10
Nodes (9): Expense, PaymentTest, TestCase, TestCase, TransactionOutstandingSyncTest, ExpenseDecoratorTest, TestCase, CategorySpendTest (+1 more)

### Community 265 - "Ai::Providers::OpenRouter"
Cohesion: 0.29
Nodes (4): Ai, Ai::Providers, Ai::Providers::OpenRouter, Provider

### Community 267 - "ExpensePlayground::Evaluations::CaseProcessor"
Cohesion: 0.21
Nodes (3): ExpensePlayground, ExpensePlayground::Evaluations, ExpensePlayground::Evaluations::CaseProcessor

### Community 268 - "Ai::Providers::FlexAi"
Cohesion: 0.33
Nodes (4): Ai, Ai::Providers, Ai::Providers::FlexAi, Provider

### Community 269 - "Ai::Providers::Mistral"
Cohesion: 0.33
Nodes (4): Ai, Ai::Providers, Ai::Providers::Mistral, Provider

### Community 270 - "Expenses::Processors::Audio"
Cohesion: 0.17
Nodes (7): Expenses, Expenses::Processors, Expenses::Processors::Audio, Base, Expenses::Processors::Audio, Expenses::Processors::Audio::Transcription, Expenses::Processors::Audio::Transcription::Result

### Community 272 - "Expenses::Inputs::DataUri"
Cohesion: 0.33
Nodes (3): Expenses, Expenses::Inputs, Expenses::Inputs::DataUri

### Community 275 - "Expenses::InputsTest"
Cohesion: 0.33
Nodes (5): Image, Expenses, Expenses::InputsTest, Expenses::InputsTest::WhatsAppImage, TestCase

### Community 276 - "Reports::Period"
Cohesion: 0.12
Nodes (4): Reports::BaseController, Reports::Period, TestCase, ReportsPeriodTest

### Community 277 - "SpeechToText::WhisperTest"
Cohesion: 0.33
Nodes (4): TestCase, SpeechToText, SpeechToText::WhisperTest, SpeechToText::WhisperTest::FakeStatus

### Community 278 - "EvaluationCase"
Cohesion: 0.15
Nodes (4): ExpensePlaygroundEvaluationCaseJob, EvaluationCase, EvaluationRunTest, TestCase

### Community 280 - "Expenses::Processors::Base"
Cohesion: 0.25
Nodes (3): Expenses, Expenses::Processors, Expenses::Processors::Base

### Community 281 - "FinancialSetupsControllerTest"
Cohesion: 0.25
Nodes (3): ImportPipeline::Result, FinancialSetupsControllerTest, IntegrationTest

### Community 282 - ".call"
Cohesion: 0.20
Nodes (3): call(), Payments, Payments::Apply

### Community 283 - "Expenses::RowResolver"
Cohesion: 0.16
Nodes (3): Expenses, Expenses::RowResolver, Expenses::RowResolver::Result

### Community 284 - "Ai"
Cohesion: 0.50
Nodes (3): Ai, Ai::SpreadsheetMapperTest, TestCase

### Community 285 - "Ai"
Cohesion: 0.50
Nodes (3): Ai, Ai::ProvidersTest, TestCase

### Community 286 - "whatsapp_business_tools"
Cohesion: 0.18
Nodes (10): mcp, whatsapp_business_tools, clientId, clientSecret, scope, $schema, enabled, oauth (+2 more)

### Community 290 - "WillPaginate::ActionView::BootstrapLinkRenderer"
Cohesion: 0.24
Nodes (4): WillPaginate, WillPaginate::ActionView, WillPaginate::ActionView::BootstrapLinkRenderer, LinkRenderer

### Community 291 - "Ai::Tasks::CategorySuggestion"
Cohesion: 0.14
Nodes (6): Ai, Ai::Tasks, Ai::Tasks::CategorySuggestion, Base, Ai::Tasks::CategorySuggestionTest, TestCase

### Community 292 - "ExpenseResolver::AmountResult"
Cohesion: 0.18
Nodes (3): ExpenseResolver, ExpenseResolver::AmountResult, ExpenseResolver::AmountResult::Result

### Community 293 - "financial_chat.js"
Cohesion: 0.29
Nodes (16): addUserBubble(), appendDelta(), autoGrow(), completeStreaming(), csrfToken(), currentTime(), escapeHtml(), failStreaming() (+8 more)

### Community 294 - ".success?"
Cohesion: 0.18
Nodes (3): ServiceResult, Statements, Statements::Parser

### Community 295 - "AiRequest"
Cohesion: 0.20
Nodes (4): AiRequest, Ai, Ai::MetricsTest, TestCase

### Community 297 - "Payments::BalanceEffect"
Cohesion: 0.21
Nodes (3): MoneySources::BalanceSync, Payments, Payments::BalanceEffect

### Community 298 - "TransactionRules::SuggestionServiceTest"
Cohesion: 0.40
Nodes (3): TestCase, TransactionRules, TransactionRules::SuggestionServiceTest

### Community 299 - "ExpensePlayground::Evaluations::ResultBuilder"
Cohesion: 0.38
Nodes (3): ExpensePlayground, ExpensePlayground::Evaluations, ExpensePlayground::Evaluations::ResultBuilder

### Community 301 - "Expenses::Inputs::TextImage"
Cohesion: 0.29
Nodes (4): Expenses, Expenses::Inputs, Expenses::Inputs::TextImage, Base

### Community 302 - "RSpec Standards"
Cohesion: 0.12
Nodes (16): Controller Specs, Descriptions, File Structure, Guiding Principles, Model spec ordering, Model Spec Template, Quality Loop, Related Skills (+8 more)

### Community 312 - "ExpenseResolver::CategoryResult"
Cohesion: 0.17
Nodes (3): ExpenseResolver, ExpenseResolver::CategoryResult, ExpenseResolver::CategoryResult::Result

### Community 314 - "Reports::Transfers"
Cohesion: 0.24
Nodes (4): BaseController, Reports::TransfersController, Base, Reports::Transfers

### Community 315 - "Statements::Confirmation"
Cohesion: 0.10
Nodes (7): Categories, Categories::ClosestResolver::Result, StandardError, Statements, Statements::Confirmation, Statements::Confirmation::CategoryResolution, Statements::Confirmation::RollbackWithErrors

### Community 318 - "Ruby Standards"
Cohesion: 0.13
Nodes (14): Classes and Modules, Comments, Errors and Edge Cases, Guiding Principles, Inline comments, Methods and Flow, Naming, Object-Oriented Design (+6 more)

### Community 319 - "Expenses::Inputs::Text"
Cohesion: 0.33
Nodes (4): Expenses, Expenses::Inputs, Expenses::Inputs::Text, Base

### Community 322 - "CreditAccount"
Cohesion: 0.19
Nodes (5): CreditAccount, adjust!(), backfill!(), MoneySources, MoneySources::OutstandingSync

### Community 323 - "questions.rb"
Cohesion: 0.28
Nodes (15): build_text(), candidate_label(), category_rows(), deliver(), direct_question(), expense_context(), format_amount(), grouped_question() (+7 more)

### Community 324 - "Expenses::FileImport::Readers::Extraction"
Cohesion: 0.33
Nodes (3): Expenses::FileImport::Readers::Extraction, Expenses::FileImport::Readers::Xlsx, Base

### Community 325 - "Ai::RouterTest::FakeTask"
Cohesion: 0.17
Nodes (5): Ai, Ai::RouterTest, Ai::RouterTest::FakeTask, Base, TestCase

### Community 326 - "Ai::Tasks::ConversationExpenseParsing"
Cohesion: 0.18
Nodes (6): Ai, Ai::Tasks, Ai::Tasks::ConversationExpenseParsing, Base, Ai::Tasks::ConversationExpenseParsingTest, TestCase

### Community 328 - "Expense Tracker Design System"
Cohesion: 0.15
Nodes (12): Badges and icons, Expense Tracker Design System, Forms, Global chrome (application.html.erb), HTML mockups (design stage), Index/list pages, Money and amounts, Navigation (+4 more)

### Community 329 - "Expenses"
Cohesion: 0.50
Nodes (3): Expenses, Expenses::InputTest, TestCase

### Community 331 - "Expenses::FileImport::Pipeline"
Cohesion: 0.29
Nodes (3): Expenses, Expenses::FileImport, Expenses::FileImport::Pipeline

### Community 332 - ".call"
Cohesion: 0.08
Nodes (12): Ai, Ai::Tasks, Ai::Tasks::ParsedExpense, ExpenseResolver, ExpenseResolver::Amounts, ExpenseResolver::Amounts::Service, ExpenseResolver, ExpenseResolver::HeuristicParser (+4 more)

### Community 334 - "FinancialChatChannel"
Cohesion: 0.38
Nodes (4): broadcast(), FinancialChatChannel, stream_name_for(), Channel

### Community 336 - ".call"
Cohesion: 0.18
Nodes (7): call(), MoneySources, MoneySources::BalanceAdjust, call(), Reconciliation, Reconciliation::CheckBalance, Reconciliation::CheckBalance::Result

### Community 337 - "parser_test.rb"
Cohesion: 0.20
Nodes (5): call(), TestCase, Statements, Statements::ParserTest, Statements::ParserTest::FakeExtractor

### Community 339 - "BulletIntegrationHook"
Cohesion: 0.33
Nodes (4): ActionDispatch, ActionDispatch::IntegrationTest, ActiveSupport, BulletIntegrationHook

### Community 340 - "ExpenseResolver::DateResult"
Cohesion: 0.11
Nodes (6): ExpenseResolver, ExpenseResolver::DateResult, ExpenseResolver::DateResult::Result, ExpenseResolver, ExpenseResolver::Dates, ExpenseResolver::Dates::Service

### Community 341 - "WebHookHandler::WhatsappService"
Cohesion: 0.17
Nodes (4): WebHookHandler, WebHookHandler::WhatsappService, Whatsapp, Whatsapp::GarbageFilter

### Community 342 - "MoneySources::Match"
Cohesion: 0.15
Nodes (5): MoneySources, MoneySources::Match, MoneySources, MoneySources::MatchTest, TestCase

### Community 343 - "Project Context"
Cohesion: 0.22
Nodes (8): Feature-Level READMEs, Priority, Project Context, Related Skills, Required Reading, Root README, When Context is Missing, When to Use This Skill

### Community 344 - "ExpensePlayground::DuplicateDetectorTest"
Cohesion: 0.33
Nodes (3): ExpensePlayground, ExpensePlayground::DuplicateDetectorTest, TestCase

### Community 346 - "ApplicationJob"
Cohesion: 0.29
Nodes (3): ApplicationJob, Base, GmailSetupSyncJob

### Community 347 - "ExpenseResolver"
Cohesion: 0.40
Nodes (4): ExpenseResolver, ExpenseResolver::Text, ExpenseResolver::Text::ServiceTest, TestCase

### Community 351 - ".call"
Cohesion: 0.24
Nodes (4): Expenses, Expenses::Create, Expenses::Create::Invalid, StandardError

### Community 352 - "Expenses::MoneySourceDetectionTest"
Cohesion: 0.40
Nodes (3): Expenses, Expenses::MoneySourceDetectionTest, TestCase

### Community 353 - "ExpenseResolver"
Cohesion: 0.50
Nodes (3): ExpenseResolver, ExpenseResolver::AmountResultTest, TestCase

### Community 356 - "ExpensePlayground::EvaluationTest"
Cohesion: 0.40
Nodes (3): ExpensePlayground, ExpensePlayground::EvaluationTest, TestCase

### Community 357 - "Expenses::FileImport::Enrichers::MoneySource"
Cohesion: 0.25
Nodes (4): Expenses, Expenses::FileImport, Expenses::FileImport::Enrichers, Expenses::FileImport::Enrichers::MoneySource

### Community 358 - "ExpenseResolver"
Cohesion: 0.40
Nodes (4): ExpenseResolver, ExpenseResolver::Dates, ExpenseResolver::Dates::ServiceTest, TestCase

### Community 361 - "Expenses::FileImport::ImportContext"
Cohesion: 0.20
Nodes (3): Expenses, Expenses::FileImport, Expenses::FileImport::ImportContext

### Community 362 - "Categories"
Cohesion: 0.50
Nodes (3): Categories, Categories::DecisionTest, TestCase

### Community 363 - "Expenses::FileProcessorTest"
Cohesion: 0.18
Nodes (3): Expenses, Expenses::FileProcessorTest, TestCase

### Community 365 - "ExpenseResolver"
Cohesion: 0.50
Nodes (3): ExpenseResolver, ExpenseResolver::DateResultTest, TestCase

### Community 367 - "Expenses::Processors::Image"
Cohesion: 0.28
Nodes (4): Expenses, Expenses::Processors, Expenses::Processors::Image, Base

### Community 369 - "ReconciliationSnapshot"
Cohesion: 0.17
Nodes (6): ReconciliationSnapshot, Reconciliation, Reconciliation::Invalidate, call(), Reconciliation, Reconciliation::LeavePending

### Community 370 - "Expenses::Clarification::Resolver"
Cohesion: 0.22
Nodes (4): Expenses, Expenses::Clarification, Expenses::Clarification::Questions, Expenses::Clarification::Resolver

### Community 372 - "Expenses::SearchTest"
Cohesion: 0.29
Nodes (3): Expenses, Expenses::SearchTest, TestCase

### Community 373 - "Expenses::Processors::Text"
Cohesion: 0.31
Nodes (4): Expenses, Expenses::Processors, Expenses::Processors::Text, Base

### Community 374 - "Expenses::Inputs::Image"
Cohesion: 0.33
Nodes (4): Expenses, Expenses::Inputs, Expenses::Inputs::Image, Base

### Community 375 - ".call"
Cohesion: 0.27
Nodes (3): call(), Expenses, Expenses::Processor

### Community 376 - ".create"
Cohesion: 0.25
Nodes (3): FinancialChats, FinancialChats::MessagesController, FinancialChatJob

### Community 380 - "Expenses::FileImport::Enrichers::Confidence"
Cohesion: 0.33
Nodes (4): Expenses, Expenses::FileImport, Expenses::FileImport::Enrichers, Expenses::FileImport::Enrichers::Confidence

### Community 381 - "recurring_template_processor.rb"
Cohesion: 0.48
Nodes (6): call(), coerce_date(), failure(), normalize_amount(), period_range_for(), RecurringTemplateProcessor::Result

### Community 382 - "ApplicationController"
Cohesion: 0.10
Nodes (5): AlertSettingsController, ApplicationController, Base, MonthlyReportsController, WhatsappSettingsController

### Community 386 - "ApplicationRecord"
Cohesion: 0.13
Nodes (6): AlertPreference, ApplicationRecord, Base, ExpenseClarificationCandidate, ReconciliationState, WhatsappInboundMessage

### Community 391 - "Expenses"
Cohesion: 0.40
Nodes (3): Expenses, Expenses::FileImport, Expenses::FileImport::Readers

### Community 393 - "Expenses::Processors::Recording"
Cohesion: 0.25
Nodes (3): Expenses, Expenses::Processors, Expenses::Processors::Recording

### Community 394 - "Expenses::FileImport::Readers::Csv"
Cohesion: 0.17
Nodes (7): Expenses, Expenses::FileImport, Expenses::FileImport::Readers, Expenses::FileImport::Readers::Csv, Base, ExpenseEvaluationsControllerTest, IntegrationTest

### Community 396 - "MoneySources::BalanceSyncTest"
Cohesion: 0.29
Nodes (3): MoneySources, MoneySources::BalanceSyncTest, TestCase

### Community 398 - "SourceRecognition::SuggestionEngine"
Cohesion: 0.11
Nodes (6): SourceRecognition, SourceRecognition::SuggestionEngine, SourceRecognition::SuggestionEngine::Suggestion, TestCase, SourceRecognition, SourceRecognition::SuggestionEngineTest

### Community 399 - "Expenses"
Cohesion: 0.50
Nodes (3): Expenses, Expenses::FileImport, Expenses::FileImport::Enrichers

### Community 401 - ".stub_method"
Cohesion: 0.21
Nodes (5): Ai::Router::Result, Expenses, Expenses::Clarification, Expenses::Clarification::ResolverTest, TestCase

### Community 402 - "ai_entry_rules.spec.js"
Cohesion: 0.33
Nodes (3): { pickCategory }, { signUp, createCategory }, { test, expect }

### Community 403 - "file_import/result.rb"
Cohesion: 0.50
Nodes (3): Expenses, Expenses::FileImport, Expenses::FileImport::Result

### Community 405 - ".call"
Cohesion: 0.47
Nodes (4): download(), fetch_media_url(), Whatsapp, Whatsapp::MediaFetcher

### Community 406 - "Expenses::FileImport::TabularParser"
Cohesion: 0.31
Nodes (4): Expenses, Expenses::FileImport, Expenses::FileImport::TabularParser, Expenses::FileImport::TabularParser::Mapping

### Community 407 - "EmailTransactionDetectorTest"
Cohesion: 0.22
Nodes (4): EmailTransactionDetector, EmailTransactionDetector::Result, EmailTransactionDetectorTest, TestCase

### Community 408 - ".process_file"
Cohesion: 0.40
Nodes (3): call(), Expenses, Expenses::FileProcessor

### Community 410 - "Ai::Tasks::ClarificationResolution"
Cohesion: 0.29
Nodes (4): Ai, Ai::Tasks, Ai::Tasks::ClarificationResolution, Base

### Community 412 - "Ai"
Cohesion: 0.40
Nodes (4): Ai, Ai::Tasks, Ai::Tasks::ClarificationResolutionTest, TestCase

### Community 413 - "ExpenseResolverServiceTest"
Cohesion: 0.20
Nodes (4): ExpenseResolver, ExpenseResolver::HeuristicResolver::Resolution, ExpenseResolverServiceTest, TestCase

### Community 414 - "Reports::SpendingTrend"
Cohesion: 0.12
Nodes (6): BaseController, Reports::SpendingTrendController, Base, Reports::SpendingTrend, TestCase, ReportsSpendingTrendTest

### Community 417 - "garbage_filter.rb"
Cohesion: 0.60
Nodes (5): garbage?(), no_expense_signal_and_noisy?(), noisy?(), token_repetition?(), unique_ratio()

### Community 425 - "Whatsapp::MediaFetcherTest"
Cohesion: 0.40
Nodes (3): TestCase, Whatsapp::MediaFetcherTest, Whatsapp::MediaFetcherTest::FakeResponse

### Community 429 - "Expenses::FileImport::Readers::Base"
Cohesion: 0.20
Nodes (4): Expenses, Expenses::FileImport, Expenses::FileImport::Readers, Expenses::FileImport::Readers::Base

### Community 430 - "Reports::MoneySources"
Cohesion: 0.15
Nodes (6): BaseController, Reports::MoneySourcesController, Base, Reports::MoneySources, TestCase, ReportsMoneySourcesTest

### Community 436 - "payments.js"
Cohesion: 0.48
Nodes (6): bindForm(), update(), componentValue(), formatMoney(), init(), toNumber()

### Community 443 - "ExpensePlayground::Evaluations::Runner"
Cohesion: 0.22
Nodes (3): ExpensePlayground, ExpensePlayground::Evaluations, ExpensePlayground::Evaluations::Runner

### Community 444 - "Whatsapp"
Cohesion: 0.50
Nodes (3): TestCase, Whatsapp, Whatsapp::GarbageFilterTest

### Community 445 - "Reports::Base"
Cohesion: 0.14
Nodes (5): Reports::Base, Base, TestCase, ReportsBaseTest, ReportsBaseTest::Probe

### Community 449 - "Expenses::CandidateDeduplicatorTest"
Cohesion: 0.40
Nodes (3): Expenses, Expenses::CandidateDeduplicatorTest, TestCase

### Community 450 - "ApplicationCable::Connection"
Cohesion: 0.33
Nodes (3): ApplicationCable, ApplicationCable::Connection, Base

### Community 451 - "Expenses::BulkDestroyTest"
Cohesion: 0.33
Nodes (3): Expenses, Expenses::BulkDestroyTest, TestCase

### Community 452 - "Expenses::FileImport::Readers::Pdf"
Cohesion: 0.33
Nodes (5): Expenses, Expenses::FileImport, Expenses::FileImport::Readers, Expenses::FileImport::Readers::Pdf, Base

### Community 455 - "Reports::Filter"
Cohesion: 0.14
Nodes (3): Reports::Filter, TestCase, ReportsFilterTest

### Community 461 - "ExpenseCandidates::BulkConfirmTest"
Cohesion: 0.40
Nodes (3): ExpenseCandidates, ExpenseCandidates::BulkConfirmTest, TestCase

### Community 462 - "ExpenseCandidates::BulkUpdateTest"
Cohesion: 0.40
Nodes (3): ExpenseCandidates, ExpenseCandidates::BulkUpdateTest, TestCase

### Community 466 - "Expenses::BulkCreateTest"
Cohesion: 0.40
Nodes (3): Expenses, Expenses::BulkCreateTest, TestCase

### Community 467 - "Expenses::BulkUpdateTest"
Cohesion: 0.40
Nodes (3): Expenses, Expenses::BulkUpdateTest, TestCase

### Community 469 - "Expenses::ConfidenceCalculatorTest"
Cohesion: 0.33
Nodes (3): Expenses, Expenses::ConfidenceCalculatorTest, TestCase

### Community 470 - "Expenses::RecurringAssignmentTest"
Cohesion: 0.40
Nodes (3): Expenses, Expenses::RecurringAssignmentTest, TestCase

### Community 471 - "Expenses::AudioProcessorTest"
Cohesion: 0.33
Nodes (3): Expenses, Expenses::AudioProcessorTest, TestCase

### Community 472 - "connection_test.rb"
Cohesion: 0.40
Nodes (4): ApplicationCable, ApplicationCable::ConnectionTest, ApplicationCable::ConnectionTest::WardenStub, TestCase

### Community 475 - "Payments::RecurringLink"
Cohesion: 0.23
Nodes (3): call(), Payments, Payments::RecurringLink

### Community 477 - "Reports::Budgets"
Cohesion: 0.21
Nodes (4): BaseController, Reports::BudgetsController, Base, Reports::Budgets

### Community 480 - "ApplicationCable"
Cohesion: 0.50
Nodes (3): ApplicationCable, ApplicationCable::Channel, Base

### Community 483 - "WhatsappIdentity"
Cohesion: 0.12
Nodes (4): WhatsappHelper, WhatsappIdentity, TestCase, WebHookHandlerWhatsappServiceTest

### Community 485 - "financial_chat_channel_test.rb"
Cohesion: 0.67
Nodes (3): FinancialChatBroadcastTest, FinancialChatChannelTest, TestCase

### Community 486 - "FinancialChats"
Cohesion: 0.50
Nodes (3): FinancialChats, FinancialChats::MessagesControllerTest, IntegrationTest

### Community 489 - "Expenses::Inputs::Rules::Audio"
Cohesion: 0.29
Nodes (4): Expenses, Expenses::Inputs, Expenses::Inputs::Rules, Expenses::Inputs::Rules::Audio

### Community 491 - "Gmail::QueryBuilderTest"
Cohesion: 0.40
Nodes (3): Gmail, Gmail::QueryBuilderTest, TestCase

### Community 500 - "Expenses::Inputs::Rules::File"
Cohesion: 0.29
Nodes (4): Expenses, Expenses::Inputs, Expenses::Inputs::Rules, Expenses::Inputs::Rules::File

### Community 506 - "Statements"
Cohesion: 0.50
Nodes (3): TestCase, Statements, Statements::BalanceEffectTest

### Community 507 - "Statements"
Cohesion: 0.50
Nodes (3): TestCase, Statements, Statements::ConfirmationTest

### Community 508 - "Statements"
Cohesion: 0.50
Nodes (3): TestCase, Statements, Statements::ReviewBuilderTest

### Community 509 - ".call"
Cohesion: 0.40
Nodes (3): call(), SourceRecognition, SourceRecognition::ApplyToSearchConfig

### Community 512 - ".for_user"
Cohesion: 0.16
Nodes (4): FinancialChatController, SpreadsheetFormatMapping, Ai, Ai::SpreadsheetMapper

### Community 515 - "ExpenseCandidates::BulkDiscardTest"
Cohesion: 0.40
Nodes (3): ExpenseCandidates, ExpenseCandidates::BulkDiscardTest, TestCase

### Community 519 - "SourceRecognition::MatcherTest"
Cohesion: 0.33
Nodes (3): TestCase, SourceRecognition, SourceRecognition::MatcherTest

### Community 522 - "ActiveSupport::TestCase"
Cohesion: 0.20
Nodes (4): ExpensePlaygroundEvaluationsRunnerTest, TestCase, ActiveSupport::TestCase, ActiveSupport::TestCase::SlowTestTiming

### Community 523 - "Expenses::ProcessorTest"
Cohesion: 0.33
Nodes (3): Expenses, Expenses::ProcessorTest, TestCase

### Community 524 - "expense-bulk-selection.spec.js"
Cohesion: 0.40
Nodes (4): createExpense(), { pickCategory }, { signUp, createCategory }, { test, expect }

### Community 531 - "Reconciliation::StateTest"
Cohesion: 0.40
Nodes (3): TestCase, Reconciliation, Reconciliation::StateTest

### Community 532 - "Ai::ImageExpenseExtractorTest"
Cohesion: 0.40
Nodes (3): Ai, Ai::ImageExpenseExtractorTest, TestCase

### Community 535 - "Expenses::RowResolverTest"
Cohesion: 0.40
Nodes (3): Expenses, Expenses::RowResolverTest, TestCase

### Community 536 - "Reconciliation"
Cohesion: 0.50
Nodes (3): TestCase, Reconciliation, Reconciliation::CheckBalanceTest

### Community 537 - "Payments::RecurringLinkTest"
Cohesion: 0.40
Nodes (3): Payments, Payments::RecurringLinkTest, TestCase

### Community 555 - "Expenses::CreateTest"
Cohesion: 0.40
Nodes (3): Expenses, Expenses::CreateTest, TestCase

### Community 556 - "Expenses"
Cohesion: 0.50
Nodes (3): Expenses, Expenses::Inputs, Expenses::Inputs::Rules

### Community 570 - ".render_csv"
Cohesion: 0.20
Nodes (5): Expenses, Expenses::CsvExporter, Expenses, Expenses::CsvExporterTest, TestCase

### Community 572 - "extraction.rb"
Cohesion: 0.50
Nodes (3): Expenses, Expenses::FileImport, Expenses::FileImport::Readers

### Community 574 - "Expenses"
Cohesion: 0.50
Nodes (3): Expenses, Expenses::FileImport, Expenses::FileImport::Readers

## Knowledge Gaps
- **407 isolated node(s):** `$schema`, `plugin`, `type`, `url`, `enabled` (+402 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 2145 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **279 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Category` connect `Category` to `.render`, `ApplicationRecord`, `Expenses::BulkUpdate`, `FinancialSetupsController`, `PaymentsControllerTest`, `ApplicationHelper`, `CategoryOptionListTest`, `Reports::Insights`, `ExpensePlaygroundController`, `FinancialSetups::Completer`, `RecurringTemplatesController`, `RecurringTemplateActions`, `.load_dashboard`, `ExpensePlayground::Evaluations::ResultBuilder`, `ExpenseCandidatesController`, `BudgetsController`, `.call`, `TransactionRules::SuggestionService`, `Statements::Confirmation`, `Expenses::BulkCreate`, `CategoriesClosestResolverTest`, `.call`, `questions.rb`, `Reports::Filter`, `ReportsHelper`, `ExpenseResolver::Service`, `Ai::CategoryClassifier`, `Expenses::ValueParsing`, `IncomesController`, `Reports::Budgets`, `.call`, `ExpenseResolverHeuristicResolverTest`, `WhatsappIdentity`, `Expenses::Processors::Image::VisionCandidateBuilder`, `RecurringTemplateImporter`, `Expenses::FileImport::ImportContext`, `TransactionRulesController`, `Expenses::Clarification::Resolver`, `.normalize_name`?**
  _High betweenness centrality (0.176) - this node is a cross-community bridge._
- **Why does `ApplicationRecord` connect `ApplicationRecord` to `.for_user`, `MoneySource`, `ExpenseClarification`, `FinancialChatMessage`, `SpendingAlert`, `RecurringTemplate`, `User`, `EvaluationRun`, `Category`, `EvaluationCase`, `FinancialSetup`, `SourceRecognition::Catalog`, `AiRequest`, `MoneySourceRecognitionIdentifier`, `ExpensePlaygroundRun`, `Transfer`, `FinancialCatalogSeeder`, `CreditAccount`, `ExpenseCandidate`, `Transaction`, `Budget`, `Gmail::ExpenseImporter`, `WhatsappIdentity`, `PendingWhatsappConnection`, `TransactionRule`, `Payment`, `ReconciliationSnapshot`, `GmailConnection`, `.normalize_name`?**
  _High betweenness centrality (0.175) - this node is a cross-community bridge._
- **Why does `ExpenseCandidate` connect `ExpenseCandidate` to `ExpensePlaygroundEvaluationsResultBuilderTest`, `Expenses::CandidateDeduplicatorTest`, `ApplicationRecord`, `ExpenseResolver::CandidateDetector`, `ExpenseCandidates::BulkDiscardTest`, `ExpenseCandidateTest`, `ExpensePlayground::EvaluationTest`, `ExpenseCandidates::BulkConfirmTest`, `ExpenseCandidates::BulkUpdateTest`, `ExpensePlaygroundController`, `ExpenseCandidatesControllerTest`, `.call`, `ExpensePlayground::DuplicateDetectorTest`, `Expenses::FileImport::CandidateBuilder`?**
  _High betweenness centrality (0.062) - this node is a cross-community bridge._
- **What connects `$schema`, `plugin`, `type` to the rest of the system?**
  _407 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `.render` be split into smaller, more focused modules?**
  _Cohesion score 0.08571428571428572 - nodes in this community are weakly interconnected._
- **Should `auth.js` be split into smaller, more focused modules?**
  _Cohesion score 0.09686609686609686 - nodes in this community are weakly interconnected._
- **Should `MoneySource` be split into smaller, more focused modules?**
  _Cohesion score 0.08735632183908046 - nodes in this community are weakly interconnected._