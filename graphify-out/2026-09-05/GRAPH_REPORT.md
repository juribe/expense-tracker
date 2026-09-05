# Graph Report - expense_tracker  (2026-09-05)

## Corpus Check
- 276 files · ~115,351 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1514 nodes · 1896 edges · 177 communities (52 shown, 98 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 57 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Gmail Connections Controller
- Expenses Controller
- ExpenseParser AI Service
- AI Entry Playwright Spec
- MoneySource Model
- Money Source Recognition Identifier
- Add Expense Form Design
- AI Statement Extractor
- Financial Setups Controller
- Import Pipeline
- Gmail Expense Importer
- Frontend JS Bindings
- AI Transaction Extractor
- Bulk Edit Expenses UI
- Application Helper
- Recurring Templates Model
- Source Recognition Matcher
- Source Recognition Suggestion Engine
- Money Sources Controller
- Gmail Query Builder
- QA Dashboard Validation
- Dashboard UI Concepts
- Category Model
- Expenses Create Service
- FinancialSetups Completer
- Source Recognition Discovery
- Config & Seed Data
- Recurring Templates Controller
- FinancialSetup Model
- FinancialSetups Step Presenter
- Gmail Client
- Gmail Sync Tests
- Recurring Template Actions
- Source Recognition Catalog
- Dashboard & Incomes Controllers
- Categories Controller
- App Models Base
- Financial Email Filter
- Models & I18n Keys
- Financial Setup Wizard UI
- App & Monthly Controllers
- Imports & Template Importer
- Expenses Helper
- Financial Keyword & Seeder
- Credit Cards & Loans
- Recurring Income/Expense UI
- Financial Setup Wizard Steps
- Source Recognition Implementation
- Transfers Controller
- Gmail Import & Money Sources
- Expense Views Table
- Source Text Normalizer
- Tag Migration
- Category Management UI
- Playwright Package Config
- Statement Duplicate Detector
- Expense Dashboard Service
- Bulk Update Expense UI
- Static Error Pages
- Import Pipeline Test
- Discovery Service Test
- Test Helper
- Devise Auth Forms
- Playwright Config
- Monthly Reports Controller
- Devise Passwords
- Devise Registrations
- Dashboard Helper
- Money Sources & Wizard
- Expenses Controller Test
- Completer Test
- Step Presenter Test
- Apply To Search Config Test
- Financial Email Filter Test
- App Application Class
- Add Devise Migration
- Category Form Fields Migration
- Backfill Transactions Migration
- Remap Legacy Links Migration
- Normalize Transaction Signs Migration
- Remove Frequency Migration
- Drop Monthly Expense Tables Migration
- Migrate Identifiers To Tags Migration
- Money Sources Controller Test
- Gmail Sync Job Test
- Financial Setup Test
- Money Source Recognition Test
- Money Source Test
- Application Brand Icon
- Application Mailer
- Completer Result
- Create Categories Migration
- Create Expenses Migration
- Create Users Migration
- Create Incomes Migration
- Create Monthly Expense Payments Migration
- Create Recurring Transactions Migration
- Create Recurring Occurrences Migration
- Create Monthly Expenses Migration
- Create Transactions Migration
- Create Recurring Templates Migration
- Add Frequency Migration
- Create Gmail Connections Migration
- Create Processed Emails Migration
- Add Gmail Message Id Migration
- Create Money Sources Migration
- Create Money Source Identifiers Migration
- Create Transfers Migration
- Add Money Source To Transactions Migration
- Add Money Source To Recurring Templates Migration
- Add Default/Custom Categories Migration
- Scope Category Uniqueness Migration
- Create Solid Queue Tables Migration
- Create Money Source Tags Migration
- Add Identifier To Money Sources Migration
- Add Value Index To Tags Migration
- Drop Money Source Identifiers Migration
- Create Credit Accounts Migration
- Create Financial Setups Migration
- Add Installments Paid Migration
- Create Money Source Recognitions Migration
- Create Financial Email Catalog Migration
- Add Discovery State Migration
- Add Sync State To Gmail Connections Migration
- Category Form & Deletion
- Categories Controller Test
- Expenses AI Entry Test
- Gmail Connections Test
- Sessions Test
- Application Helper Test
- Devise Auth Flows Test
- Category Test
- Credit Account Test
- Financial Institution Test
- Gmail Connection Test
- Processed Email Test
- Financial Setup Wizard Test
- Parsed Statement Test
- Docker Entrypoint
- Devise Translations
- App Translations
- AI Entry Page Spec
- Bulk Update Page Spec
- Monthly Income Page Spec
- Monthly Recurring Page Spec
- Categories Page Spec
- Gmail Import Page Spec
- Postgres Migration Spec
- Money Sources Page Spec
- Solid Queue Page Spec

## God Nodes (most connected - your core abstractions)
1. `ExpensesController` - 34 edges
2. `FinancialSetupsController` - 32 edges
3. `Category` - 32 edges
4. `ExpenseParser` - 32 edges
5. `MoneySource` - 29 edges
6. `Ai::StatementExtractor` - 28 edges
7. `ApplicationHelper` - 25 edges
8. `Ai::TransactionExtractor` - 22 edges
9. `MoneySourcesController` - 20 edges
10. `FinancialSetups::Completer` - 20 edges

## Surprising Connections (you probably didn't know these)
- `Source Recognition (Gmail-based Email Matching)` --references--> `Colombian Financial Institutions Catalog`  [INFERRED]
  EXPLORATION_SUMMARY.md → db/seed_data/financial_institutions.yml
- `Source Recognition (Gmail-based Email Matching)` --references--> `Financial Email Keywords Dictionary`  [INFERRED]
  EXPLORATION_SUMMARY.md → db/seed_data/financial_keywords.yml
- `Source Recognition (Gmail-based Email Matching)` --references--> `Financial Email Subject Patterns`  [INFERRED]
  EXPLORATION_SUMMARY.md → db/seed_data/financial_subject_patterns.yml
- `Categories I18n Keys (English)` --implements--> `Category Model (Nested Hierarchy)`  [EXTRACTED]
  config/locales/en.yml → EXPLORATION_SUMMARY.md
- `Categories I18n Keys (Spanish)` --implements--> `Category Model (Nested Hierarchy)`  [EXTRACTED]
  config/locales/es.yml → EXPLORATION_SUMMARY.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Email-Based Financial Transaction Matching System** — db_seed_data_financial_institutions, db_seed_data_financial_keywords, db_seed_data_financial_subject_patterns, exploration_summary_source_recognition, gmail_sync_job_rationale [INFERRED 0.85]
- **Core Expense Domain Model Graph** — exploration_summary_expense_model, exploration_summary_category_model, exploration_summary_user_model, exploration_summary_monthly_expense_model, exploration_summary_monthly_expense_payment_model [EXTRACTED 1.00]
- **Bilingual I18n Layer (English/Spanish)** — config_locales_devise_en, config_locales_devise_es, config_locales_en, config_locales_es [EXTRACTED 1.00]
- **Credit Card & Loan Debt Source Flow** — designs_credit_cards_and_loans_loan_kind, designs_credit_cards_and_loans_creditaccount, designs_design_develop_hybrid_financial_setup_wizard_financialsetupwizard, designs_design_definition_money_sources_accounts_cards_wallets_transfers_matching_moneysources [EXTRACTED 0.85]
- **Expenses Index Surface (Table/Filters/Bulk)** — designs_design_expense_views_table_expenseviewstable, designs_design_expense_list_filters_expenselistfilters, designs_bulk_update_expense_category_and_money_source_bulkupdate [INFERRED 0.85]
- **Expense Entry Workflow** — docs_designs_design_add_expense_form_md, docs_designs_design_add_expense_form_md_validation_states, docs_designs_design_add_expense_form_md_category_dropdown, docs_designs_review_expense_form_design_md, docs_mockups_review_expense_form_design_html [INFERRED 0.85]
- **Category Selection Pattern** — docs_designs_design_add_expense_form_md_category_dropdown, docs_designs_design_category_management_md, docs_designs_design_dashboard_ui_ux_md_filter_bar [INFERRED 0.75]
- **Source Recognition Feature** — docs_source_recognition_implementation_md_money_source_recognition, docs_source_recognition_implementation_md_suggestion_engine, docs_source_recognition_implementation_md_recognition_controller, docs_source_recognition_implementation_md_gmail_guard [EXTRACTED 1.00]
- **Expense CRUD Operations** — mockups_bulk_update_expense_category_and_money_source_expensetable, mockups_design_add_expense_form_expenseform, mockups_design_expense_views_table_expensetable, concept_expense_data_model [INFERRED 0.85]
- **Money Source Lifecycle** — mockups_credit_cards_and_loans_moneysourceindex, mockups_credit_cards_and_loans_moneysourceform, mockups_design_definition_money_sources_accounts_cards_wallets_transfers_matching_moneysourcesindex, mockups_design_develop_hybrid_financial_setup_wizard_manualentry, concept_money_source_data_model [INFERRED 0.80]
- **Category Management Workflow** — mockups_category_form_design_and_implementation_categoryform, mockups_design_category_management_categorygrouplist, mockups_design_category_management_categorylist, concept_category_data_model [INFERRED 0.85]
- **Rails Default Error Page Template Family** — public_400_html, public_404_html, public_406_unsupported_browser_html, public_422_html, public_500_html [EXTRACTED 1.00]
- **Application Icon in Multiple Formats** — public_icon_png, public_icon_svg, app_brand_icon [INFERRED 0.90]
- **Public Static Web Assets** — public_400_html, public_404_html, public_406_unsupported_browser_html, public_422_html, public_500_html, public_robots_txt, public_icon_png, public_icon_svg [INFERRED 0.85]

## Communities (177 total, 98 thin omitted)

### Community 0 - "Gmail Connections Controller"
Cohesion: 0.05
Nodes (23): GmailConnectionsController, ApplicationJob, Base, GmailSyncJob, EncryptedSecret, encrypts_secret(), secret_encryptor(), GmailConnection (+15 more)

### Community 1 - "Expenses Controller"
Cohesion: 0.06
Nodes (9): ExpensesController, Expense, Transaction, call(), coerce_date(), failure(), normalize_amount(), period_range_for() (+1 more)

### Community 2 - "ExpenseParser AI Service"
Cohesion: 0.07
Nodes (8): call(), ExpenseParser, ExpenseParser::AIError, ExpenseParser::Resolution, StandardError, ParsedExpense, ExpenseParserTest, TestCase

### Community 3 - "AI Entry Playwright Spec"
Cohesion: 0.06
Nodes (29): FakeRecognition, PARSE_RESPONSE, { signUp }, { test, expect }, { signUp }, { test, expect }, { signUp, signIn }, { test, expect } (+21 more)

### Community 4 - "MoneySource Model"
Cohesion: 0.05
Nodes (7): MoneySource, MoneySources, MoneySources::Match, SanitizeMoneySourceIdentifiersToLastFour, MoneySources, MoneySources::MatchTest, TestCase

### Community 5 - "Money Source Recognition Identifier"
Cohesion: 0.05
Nodes (14): MoneySourceRecognitionIdentifier, MoneySourceRecognition, EmailTransactionDetector, EmailTransactionDetector::Result, call(), SourceRecognition, SourceRecognition::ApplyToSearchConfig, EmailTransactionDetectorTest (+6 more)

### Community 6 - "Add Expense Form Design"
Cohesion: 0.06
Nodes (38): Add Expense Form Design Spec, Bootstrap 5 Components, Category Dropdown, Centered Modal or Card Layout, Bootstrap 5 Color Palette, Form Validation States, Category Management UI/UX Spec, Custom Category Grouping (+30 more)

### Community 7 - "AI Statement Extractor"
Cohesion: 0.10
Nodes (8): Ai, Ai::StatementExtractor, Ai::StatementExtractor::ExtractionError, parse(), StandardError, Ai, Ai::StatementExtractorTest, TestCase

### Community 9 - "Import Pipeline"
Cohesion: 0.09
Nodes (7): ImportPipeline, ImportPipeline::Result, ParsedStatement, FinancialSetupsControllerTest, IntegrationTest, TestCase, StatementDuplicateDetectorTest

### Community 10 - "Gmail Expense Importer"
Cohesion: 0.11
Nodes (7): ProcessedEmail, Gmail, Gmail::ExpenseImporter, Gmail::ExpenseImporter::Result, call(), Gmail, Gmail::SyncService

### Community 11 - "Frontend JS Bindings"
Cohesion: 0.12
Nodes (25): bindAvailableCredit(), bindForm(), bindInput(), bindRecognition(), formatCurrencyNumber(), formatInput(), formatValue(), gmailSyncStatusPath() (+17 more)

### Community 12 - "AI Transaction Extractor"
Cohesion: 0.11
Nodes (8): Ai, Ai::TransactionExtractor, Ai::TransactionExtractor::ExtractionError, parse(), StandardError, Ai, Ai::TransactionExtractorTest, TestCase

### Community 13 - "Bulk Edit Expenses UI"
Cohesion: 0.08
Nodes (27): Bulk Bar (Expenses index), Bulk Update Expense Category and Money Source, category_badge Helper, ExpensesController#bulk_update, MoneySource.active Scope, MoneySource#display_name, Recurring Transactions UI (Income & Expense), Monthly Recurring Expenses UI (+19 more)

### Community 15 - "Recurring Templates Model"
Cohesion: 0.09
Nodes (6): RecurringTemplate, Transfer, IntegrationTest, TransfersControllerTest, TestCase, TransferTest

### Community 16 - "Source Recognition Matcher"
Cohesion: 0.13
Nodes (6): call(), SourceRecognition, SourceRecognition::Matcher, TestCase, SourceRecognition, SourceRecognition::MatcherTest

### Community 17 - "Source Recognition Suggestion Engine"
Cohesion: 0.11
Nodes (6): SourceRecognition, SourceRecognition::SuggestionEngine, SourceRecognition::SuggestionEngine::Suggestion, TestCase, SourceRecognition, SourceRecognition::SuggestionEngineTest

### Community 19 - "Gmail Query Builder"
Cohesion: 0.11
Nodes (6): build(), Gmail, Gmail::QueryBuilder, Gmail, Gmail::QueryBuilderTest, TestCase

### Community 21 - "Dashboard UI Concepts"
Cohesion: 0.16
Nodes (18): Category Data Model, Expense Data Model, Dashboard Example, Category Breakdown Chart, Recent Transactions List, Dashboard Stat Cards, Add Expense Form Design, Expense Entry Form (+10 more)

### Community 23 - "Expenses Create Service"
Cohesion: 0.15
Nodes (7): Expenses, Expenses::Create, Expenses::Create::Invalid, StandardError, Expenses, Expenses::CreateTest, TestCase

### Community 25 - "Source Recognition Discovery"
Cohesion: 0.19
Nodes (4): call(), SourceRecognition, SourceRecognition::DiscoveryService, SourceRecognition::DiscoveryService::Result

### Community 26 - "Config & Seed Data"
Cohesion: 0.13
Nodes (17): ActionCable Configuration, PostgreSQL Database Configuration, Gmail Integration I18n Keys (English), Solid Queue Configuration, Recurring Tasks Configuration, ActiveStorage Configuration, Colombian Financial Institutions Catalog, Financial Email Keywords Dictionary (+9 more)

### Community 30 - "Gmail Client"
Cohesion: 0.19
Nodes (4): Gmail, Gmail::Client, Gmail::Client::Error, StandardError

### Community 31 - "Gmail Sync Tests"
Cohesion: 0.14
Nodes (6): configure(), Gmail, Gmail::SyncServiceTest, Gmail::SyncServiceTest::FakeClient, Gmail::SyncServiceTest::FakeExtractor, TestCase

### Community 33 - "Source Recognition Catalog"
Cohesion: 0.22
Nodes (3): FinancialInstitution, SourceRecognition, SourceRecognition::Catalog

### Community 34 - "Dashboard & Incomes Controllers"
Cohesion: 0.18
Nodes (3): DashboardController, IncomesController, Income

### Community 36 - "App Models Base"
Cohesion: 0.18
Nodes (4): ApplicationRecord, Base, CreditAccount, FinancialSubjectPattern

### Community 37 - "Financial Email Filter"
Cohesion: 0.24
Nodes (4): call(), SourceRecognition, SourceRecognition::FinancialEmailFilter, SourceRecognition::FinancialEmailFilter::Result

### Community 38 - "Models & I18n Keys"
Cohesion: 0.24
Nodes (12): Categories I18n Keys (English), Expenses I18n Keys (English), Categories I18n Keys (Spanish), Expenses I18n Keys (Spanish), Category Model (Nested Hierarchy), Dashboard (Summary Cards, Quick Add, Recent Expenses), Devise Authentication Rationale, Expense Model (+4 more)

### Community 39 - "Financial Setup Wizard UI"
Cohesion: 0.17
Nodes (12): Money Source Form, Hybrid Financial Setup Wizard, Setup Complete State, Duplicate Card Handling, Extraction Review Step, Statement File Upload, Final Review Step, Manual Account Entry (+4 more)

### Community 40 - "App & Monthly Controllers"
Cohesion: 0.18
Nodes (4): ApplicationController, Base, MonthlyExpensesController, MonthlyIncomesController

### Community 44 - "Credit Cards & Loans"
Cohesion: 0.18
Nodes (11): Debt Visualization Pattern, Sidebar Navigation Pattern, Credit Cards and Loans, Active Installments Table, Assets and Money Group, Credit and Debt Group, Credit Card Detail View, Credit Utilization Bar (+3 more)

### Community 45 - "Recurring Income/Expense UI"
Cohesion: 0.24
Nodes (11): Recurring Transaction Data Model, Support Monthly Income and Payments, Expense Tab, Income Tab, Pay Expense Modal, Receive Income Modal, Recurring Transactions Tab, Support Monthly Recurring Expenses (+3 more)

### Community 46 - "Financial Setup Wizard Steps"
Cohesion: 0.22
Nodes (3): choice?(), FinancialSetupWizard::Step, valid_choice!()

### Community 47 - "Source Recognition Implementation"
Cohesion: 0.31
Nodes (10): Source Recognition Implementation Guide, Recognition Edit Panel, Gmail Connection Guard, MoneySourceRecognition Data Model, MoneySourceRecognitionIdentifier Data Model, Recognition Configured Predicate, Recognition Controller Action, Suggestion Chips UI (+2 more)

### Community 49 - "Gmail Import & Money Sources"
Cohesion: 0.25
Nodes (9): Gmail Import and Matching Flow, Money Source Data Model, Transfer Data Model, Wizard Multi-Step Pattern, Money Sources Definition, Gmail Import Review Queue, Money Sources Index View, Source Chooser for Forms (+1 more)

### Community 50 - "Expense Views Table"
Cohesion: 0.22
Nodes (9): State Management Pattern, Expense Views Table, Bulk Action Bar, CSV Export, Delete Confirmation Modal, Expense Detail Drawer, Expense Table with Sorting, Filter Chips (+1 more)

### Community 52 - "Tag Migration"
Cohesion: 0.43
Nodes (5): MigrateTagsToRecognitionIdentifiers, MigrateTagsToRecognitionIdentifiers::MigrationIdentifier, MigrateTagsToRecognitionIdentifiers::MigrationRecognition, MigrateTagsToRecognitionIdentifiers::MigrationTag, Base

### Community 53 - "Category Management UI"
Cohesion: 0.25
Nodes (8): Category Form Design and Implementation, Category Create Edit Form, Category Management Design, Add Category Modal, Add Group Modal, Category Group List, Category List, Delete Group Confirmation Modal

### Community 54 - "Playwright Package Config"
Cohesion: 0.25
Nodes (7): devDependencies, @playwright/test, name, private, scripts, test:e2e, @playwright/test

### Community 57 - "Bulk Update Expense UI"
Cohesion: 0.29
Nodes (7): Bulk Operations Pattern, Bulk Update Expense Category and Money Source, Bulk Actions Bar, Change Category Modal, Expense Table, Change Money Source Modal, Expense Filter Form

### Community 58 - "Static Error Pages"
Cohesion: 0.48
Nodes (7): 400 Bad Request Error Page, 404 Not Found Error Page, 406 Unsupported Browser Error Page, 422 Unprocessable Entity Error Page, 500 Internal Server Error Page, Robots.txt Web Crawler Configuration, Rails Default Error Page Template Pattern

### Community 59 - "Import Pipeline Test"
Cohesion: 0.29
Nodes (3): ImportPipelineTest, ImportPipelineTest::FakeExtractor, TestCase

### Community 60 - "Discovery Service Test"
Cohesion: 0.29
Nodes (3): TestCase, SourceRecognition, SourceRecognition::DiscoveryServiceTest

### Community 62 - "Devise Auth Forms"
Cohesion: 0.33
Nodes (6): Authentication Flow, Devise Authentication Forms, Forgot Password Form, Reset Password Form, Sign In Form, Sign Up Form

### Community 63 - "Playwright Config"
Cohesion: 0.33
Nodes (5): { defineConfig }, fs, path, rubyVersionFile, rvm

### Community 68 - "Money Sources & Wizard"
Cohesion: 0.40
Nodes (5): Money Sources I18n Keys (English), Wizard I18n Keys (English), MoneySource (Accounts, Credit Cards, Loans), Transfer Between Money Sources, Financial Setup Wizard

### Community 71 - "Step Presenter Test"
Cohesion: 0.40
Nodes (3): FinancialSetups, FinancialSetups::StepPresenterTest, TestCase

### Community 72 - "Apply To Search Config Test"
Cohesion: 0.40
Nodes (3): TestCase, SourceRecognition, SourceRecognition::ApplyToSearchConfigTest

### Community 73 - "Financial Email Filter Test"
Cohesion: 0.40
Nodes (3): TestCase, SourceRecognition, SourceRecognition::FinancialEmailFilterTest

### Community 74 - "App Application Class"
Cohesion: 0.50
Nodes (3): Application, ExpenseTracker, ExpenseTracker::Application

### Community 88 - "Application Brand Icon"
Cohesion: 1.00
Nodes (3): Application Brand Icon, Application Icon (PNG Raster), Application Icon (SVG Vector)

### Community 124 - "Category Form & Deletion"
Cohesion: 0.67
Nodes (3): Category Form (Create/Edit), Category Management, Category Deletion: Reassign or Archive

## Knowledge Gaps
- **151 isolated node(s):** `FinancialSetupWizard::Step`, `FinancialSetups::Completer::Result`, `RecurringTemplateProcessor::Result`, `SourceRecognition::DiscoveryService::Result`, `SourceRecognition::FinancialEmailFilter::Result` (+146 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 726 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **98 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `ApplicationRecord` connect `App Models Base` to `Gmail Connections Controller`, `Source Recognition Catalog`, `Expenses Controller`, `MoneySource Model`, `Money Source Recognition Identifier`, `Gmail Expense Importer`, `Financial Keyword & Seeder`, `Recurring Templates Model`, `QA Dashboard Validation`, `Category Model`, `FinancialSetup Model`?**
  _High betweenness centrality (0.142) - this node is a cross-community bridge._
- **Why does `Category` connect `Category Model` to `Recurring Template Actions`, `Expenses Controller`, `Dashboard & Incomes Controllers`, `Categories Controller`, `App Models Base`, `MoneySource Model`, `Financial Setups Controller`, `Imports & Template Importer`, `Expenses Create Service`, `Recurring Templates Controller`?**
  _High betweenness centrality (0.098) - this node is a cross-community bridge._
- **Why does `ApplicationController` connect `App & Monthly Controllers` to `Gmail Connections Controller`, `Expenses Controller`, `Dashboard & Incomes Controllers`, `Categories Controller`, `Monthly Reports Controller`, `Financial Setups Controller`, `Imports & Template Importer`, `Transfers Controller`, `Money Sources Controller`, `QA Dashboard Validation`, `Recurring Templates Controller`?**
  _High betweenness centrality (0.088) - this node is a cross-community bridge._
- **What connects `FinancialSetupWizard::Step`, `FinancialSetups::Completer::Result`, `RecurringTemplateProcessor::Result` to the rest of the system?**
  _151 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Gmail Connections Controller` be split into smaller, more focused modules?**
  _Cohesion score 0.052525252525252523 - nodes in this community are weakly interconnected._
- **Should `Expenses Controller` be split into smaller, more focused modules?**
  _Cohesion score 0.055272108843537414 - nodes in this community are weakly interconnected._
- **Should `ExpenseParser AI Service` be split into smaller, more focused modules?**
  _Cohesion score 0.07227891156462585 - nodes in this community are weakly interconnected._