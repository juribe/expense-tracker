# Project Exploration Summary
## Expense Tracker (Rails 8.0.3)

### 1. Ruby on Rails Version
- **Rails 8.0.3** (specified in `Gemline` `gem "rails", "~> 8.0.3"`)
- `config.load_defaults 8.0` in `config/application.rb`
- Ruby 3.3.4 (from `.ruby-version`)
- Propshaft asset pipeline (modern Rails asset pipeline)

### 2. Expense Model and Schema
**Model**: `app/models/expense.rb`
- `belongs_to :user`, `belongs_to :category`
- Scopes:
  - `for_user(user)` — filters by user_id
  - `in_month(date)` — expenses within a month range (`created_at: beginning_of_month..end_of_month`)
  - `recent(limit = 5)` — ordered by created_at desc, limited N
  - `in_category(category_id)` — filters by category_id
- Class method `dashboard_summary(user:, month: Time.zone.today)` returns:
  - `total_amount` (sum of amounts)
  - `by_category` (joins categories, groups by name, sums amount)
  - `recent_expenses` (recent 5)

**Schema** (from `db/migrate/20260819150000_create_expenses.rb`):
| Column | Type | Options |
|---|---|---|
| `user_id` | references | `null: false, foreign_key: true` |
| `category_id` | references | `null: false, foreign_key: true` |
| `amount` | `decimal` | `null: false, precision: 10, scale: 2` |
| `description` | string | — |
| `date` | date | `null: false` |
| `frequency` | string | `default: 'one_time'` |
| `timestamps` | — | — |

### 3. Existing Models
| Model | Key Associations & Validations |
|---|---|
| **User** (`app/models/user.rb`) | `devise :database_authenticatable, :registerable, :recoverable, :rememberable, :validatable` <br> `has_many :expenses, dependent: :destroy` <br> `has_many :monthly_expenses, dependent: :destroy` |
| **Category** (`app/models/category.rb`) | `belongs_to :parent, class_name: 'Category', optional: true` <br> `has_many :children, class_name: 'Category', foreign_key: :parent_id, dependent: :nullify` <br> `has_many :expenses, dependent: :destroy` <br> Validates :name presence, uniqueness ; validates :slug presence, uniqueness <br> Scopes: `active`, `roots` <br> Auto-generates slug from name via `parameterize` |
| **Expense** (`app/models/expense.rb`) | See above |
| **MonthlyExpense** (`app/models/monthly_expense.rb`) | `belongs_to :user`, `belongs_to :category` <br> `has_many :monthly_expense_payments, dependent: :destroy` <br> `has_many :expenses, through: :monthly_expense_payments` <br> Validates :amount presence, numericality > 0 <br> Validates :payment_day integer 1-31 (allow_nil: true) <br> Scopes: `active`, `for_user`, `ordered` <br> Key methods: `pay!(payment_date:, amount_override:)` — creates regular Expense and payment record <br> `last_payment` — most recent payment <br> `paid_in_month?(date)` <br> `suggested_payment_date(month)` <br> `status_for(date)` <br> Inner class `PaymentError < StandardError` |
| **MonthlyExpensePayment** (`app/models/monthly_expense_payment.rb`) | `belongs_to :monthly_expense`, `belongs_to :expense` <br> Validates :one_payment_per_month — no duplicate payments in same month |

### 4. Database Migrations (7 migrations)
| Migration | Purpose |
|---|---|
| `20260819140000_create_categories.rb` | Creates `categories` table: name (unique), description, timestamps |
| `20260819150000_create_expenses.rb` | Creates `expenses` table: user, category, amount, description, date, frequency |
| `20260819200000_create_users.rb` | Creates `users` table: name (default "") |
| `20260819203838_add_devise_to_users.rb` | Adds Devise columns to users: email, encrypted_password, reset_password_token, remember_created_at |
| `20260820000000_add_category_form_fields.rb` | Adds to categories: slug (unique), parent_id, active (boolean, default true), image |
| `20260821000000_create_monthly_expenses.rb` | Creates `monthly_expenses` table: user, category, amount, description, payment_day (integer), active (boolean) |
| `20260821000010_create_monthly_expense_payments.rb` | Creates `monthly_expense_payments` table: monthly_expense, expense, payment_date; composite index on (monthly_expense_id, payment_date) |

### 5. Test Setup
- **Primary framework**: MiniTest (built-in Rails testing)
- `test/test_helper.rb` — configures parallelization, fixtures, `sign_in_as` helper using Devise `user_session_path`
- Test directories:
  - `test/controllers/` — integration tests for ExpensesController, CategoriesController, MonthlyExpensesController, SessionsController
  - `test/models/` — tests for MonthlyExpense, Category models
  - `test/integration/` — Devise auth flow tests (sign up, sign in, forgot password, reset password)
- **Playwright e2e tests** in `playwright/` directory:
  - `expenses.spec.js`, `categories.spec.js`, `dashboard.spec.js`, `auth.spec.js`, `monthly-reports.spec.js`
  - Helpers in `playwright/helpers/auth.js` (signUp, signIn, createCategory)
- No RSpec configured (`config.generators.system_tests = nil`; `rails/test_help` used throughout)

### 6. Frontend Framework
- **Bootstrap 5** (via CDN in mockups/designs, `app/assets/stylesheets` for local assets)
- **No React/Vue/Angular** — server-side rendered ERB templates with **Turbo** and **Turbolinks**
- No `app/javascript` directory (React bridge not used)
- `package.json` only has `@playwright/test` devDependency for e2e testing
- Asset pipeline: `propshaft` (Rails 8), stylesheets in `app/assets/stylesheets/`
- Bootstrap Icons (`bi-*)` used throughout UI
- Design specs reference Bootstrap 5 classes, grid, modals, badges, pills, etc.

### 7. Routes (`config/routes.rb`)
```ruby
Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  devise_for :users, controllers: {
    registrations: 'users/registrations',
    passwords: 'users/passwords'
  }

  # QA validation routes
  get 'qa/validate', to: 'qa_validate_dashboard_reports#index'
  # ... additional validate routes

  # Resources
  resources :expenses do
    collection { delete :bulk_destroy }
  end
  resources :categories
  resources :monthly_reports, only: [:index, :show]
  resources :monthly_expenses do
    member { post :pay }
  end

  # Dashboard
  get 'dashboard', to: 'dashboard#index'

  # Root
  root to: 'dashboard#index'
```

**Named routes relevant to expenses**:
- `expenses_path`, `new_expense_path`, `edit_expense_path`, `expense_path`
- `bulk_destroy_expenses_path`
- `category_path`, `new_category_path`, `edit_category_path`
- `monthly_reports_path`, `monthly_report_path`
- `monthly_expenses_path`, `new_monthly_expense_path`, `monthly_expense_path`
- `dashboard_path`, `root_path`

### 8. Expenses Controller (`app/controllers/expenses_controller.rb`)
- `before_action :authenticate_user!` — all actions require login
- `before_action :set_expense` — loads expense for show/edit/update/destroy
- `before_action :set_categories` — loads `Category.all` for forms/filters

**Actions**:
- `index` — lists expenses with filtering (category, start_date, end_date, frequency, min_amount, max_amount), sorting (date/description/category/frequency/amount), pagination (25 per page), CSV export, chip-based filter chips, bulk bar, empty/no-results/error states
- `show` — renders drawer layout (`layout: false`)
- `new` — builds expense form with `date: Date.today`
- `create` — saves expense, redirects with notice
- `edit` — renders form pre-filled
- `update` — updates expense, redirects
- `destroy` — destroys single expense, preserves filter query on redirect
- `bulk_destroy` — destroys selected expenses by IDs, handles partial failures

**Private methods**:
- `set_expense` — `current_user.expenses.find(params[:id])`
- `set_categories` — `@categories = Category.all`
- `expense_params` — permits :amount, :description, :date, :frequency, :category_id
- `filter_query` — permits :category_id, :start_date, :end_date, :frequency, :min_amount, :max_amount
- `redirect_params` — merges filter/sort/page params
- `validate_filters` — validates start_date <= end_date, min_amount <= max_amount
- `valid_date?` — iso8601 date validation
- `apply_filters` — applies category, date range, frequency, amount range filters
- `apply_sort` — applies sort column/direction
- `paginate_expenses` — will_paginate style: per_page=25, calculates @total_pages, @page, @offset
- `render_csv` — CSV generate with headers date,description,category,frequency,amount

### 9. Existing UI/Pages for Expenses

**`app/views/expenses/index.html.erb`** — Main expense list page:
- Page header with "Expenses" title, "Add Expense" button, "Export CSV" button (disabled when empty)
- Filter form with fields: Category (select), From/To date, Frequency (select), Min amount, Max amount, Filter button, Clear button
- Filter chips display active filters with close × buttons
- Results meta: "N expenses · $X,XXX.XX"
- Bulk action bar (hidden until rows selected): "N selected", Select none, Delete selected
- Table with columns: Checkbox, Date, Description, Category, Frequency, Amount, Actions
- **States**:
  - **Empty** (no expenses at all): "No expenses yet. Add your first one to see it here!"
  - **No results** (filters match nothing): "No expenses match these filters. Try clearing a filter or widening the date range."
  - **Error**: "Couldn't load expenses." + Retry link
  - **Success**: Flash notices after create/update/delete
- Pagination: prev/next numbered pages, 25 per page
- **Mobile list** stacked layout under the table
- **Loading skeletons** while Turbo fetches
- **Details drawer** (offcanvas-end): opens on row click or View button; contains dl.drawer-dl with date, amount, description, category, frequency, created, updated; footer has Edit and Delete buttons
- **Delete confirm modal**: Bootstrap modal with "This cannot be undone." message
- **JavaScript** inline in the view (Turbo-enhanced): row clicks, drawer open/close, bulk select/deselect, delete confirm, sort clicking, filter submission, CSV export

**`app/views/expenses/new.html.erb`** — Renders `_form.html.erb` partial:
- Centered card form with: Amount ($ field), Date picker, Description textarea, Category select, Frequency select, Submit/Cancel
- Error summary if validation fails

**`app/views/expenses/show.html.erb`** — Drawer detail view:
- `<dl class="drawer-dl">`: Date, Amount (currency), Description, Category badge, Frequency humanized, Created/Updated timestamps

**`app/views/expenses/_form.html.erb`** — Form partial:
- Card with header "New Expense" / "Edit Expense"
- Row: Amount + Date (each col-md-6)
- Description textarea
- Row: Category select + Frequency select
- Primary submit button

**Dashboard integration** (`app/views/dashboard/index.html.erb`):
- Summary cards: Total Balance, Expenses This Month, Category Breakdown (pie chart)
- Recent Expenses table (linked from summary)
- Quick Add Expense widget (inline form with amount, category, date, description, hidden frequency="one_time")
- Link "View all expenses" → expenses_path

### 10. Additional UI Pages
- **Categories**: Full CRUD with form, index showing nested categories with parent/child, edit/new modals
- **Dashboard**: Summary cards, recent expenses, quick add form
- **Monthly Reports**: View monthly expense summaries by month
- **Authentication**: Devise sign up, sign in, forgot password, reset password (custom inline success notices)
- **Users**: Registration (name, email, password), password updates

### File Structure Overview
```
app/
  assets/stylesheets/   -- application.css, expenses.css, dashboard.css
  controllers/          -- expenses, categories, dashboard, users
  models/               -- expense, category, user, monthly_expense, monthly_expense_payment
  views/                -- erb templates for expenses, dashboard, categories
  javascript/           -- (empty, no React/Vue/Dir)
db/
  migrate/              -- 7 migrations (see table above)
  schema.rb (generated)
config/
  routes.rb           -- full route definitions
  application.rb      -- Rails 8 defaults
  environments/         -- development.rb, test.rb, production.rb
Gemfile               -- rails 8.0.3, devise, chartkick, groupdate, propshaft, etc.
package.json          -- @playwright/test only
playwright/           -- e2e test specs + auth helpers
test/                 -- MiniTest integration & model tests
designs/              -- Markdown design specifications
mockups/              -- HTML mockups for UI design review
```