Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # WhatsApp Cloud API webhooks (public, signature-verified)
  namespace :webhooks do
    get "whatsapp", to: "whatsapp#verify"
    post "whatsapp", to: "whatsapp#webhook"
  end

  # WhatsApp linking (Settings → WhatsApp)
  get "settings/whatsapp", to: "whatsapp_settings#show", as: :whatsapp_settings
  get "settings/whatsapp/status", to: "whatsapp_settings#status", as: :status_whatsapp_settings
  delete "settings/whatsapp/pending", to: "whatsapp_settings#cancel", as: :cancel_whatsapp_settings
  delete "settings/whatsapp", to: "whatsapp_settings#destroy", as: :disconnect_whatsapp_settings

  # Devise authentication
  devise_for :users, controllers: {
    registrations: "users/registrations",
    passwords: "users/passwords"
  }

  # Allow sign out via GET as a no-JS fallback (Turbo/JS may not be loaded)
  devise_scope :user do
    get "users/sign_out", to: "devise/sessions#destroy", as: :user_session_sign_out_get
  end

  # Resources
  resources :expenses do
    collection do
      delete :bulk_destroy
      patch :bulk_update
      post :parse
      post :bulk_create
      post :assign_recurring
      post :unassign_recurring
    end
  end
  resources :expense_candidates, only: [ :index, :show, :update ] do
    member do
      post :confirm
      post :discard
      post :accept_suggestion
    end
    collection do
      patch :bulk_update
      post :bulk_confirm
      post :bulk_discard
    end
  end
  resources :incomes
  resources :categories
  resources :budgets
  resources :goals
  resources :goal_allocations, only: [ :create, :destroy ] do
    collection do
      post :reallocate
    end
  end
  resources :transaction_rules do
    collection do
      post :dismiss_suggestion
    end
    member do
      patch :toggle_active
    end
  end
  get "money_sources/cash",         to: "money_sources#index", as: :money_sources_cash, defaults: { type: "cash" }
  get "money_sources/pockets",      to: "money_sources#index", as: :money_sources_pockets, defaults: { type: "pockets" }
  get "money_sources/credit_cards", to: "money_sources#index", as: :money_sources_credit_cards, defaults: { type: "credit_cards" }
  get "money_sources/loans",        to: "money_sources#index", as: :money_sources_loans, defaults: { type: "loans" }
  # Source Recognition: manage how money sources appear in emails
  get "money_sources/recognition", to: "money_sources#recognition", as: :money_sources_recognition
  patch "money_sources/recognition/:money_source_id", to: "money_sources#update_recognition", as: :money_source_recognition
  delete "money_sources/recognition/:money_source_id", to: "money_sources#destroy_recognition", as: :money_source_recognition_destroy
  resources :money_sources, id: /[0-9]+/ do
    member do
      post :reset_adjustment
    end
    get "credits", to: "credits#show", as: :credits
    get "credits/reconstruct", to: "credits#reconstruct", as: :credit_reconstruct
    post "credits", to: "credits#build", as: :credit_build
    post "credits/refresh", to: "credits#refresh", as: :credit_refresh
    post "credits/scenarios", to: "credits#create_scenario", as: :credit_scenarios
    delete "credits/scenarios/:scenario_id", to: "credits#destroy_scenario", as: :credit_scenario
    post "extra_payments", to: "extra_payments#create", as: :extra_payments
    delete "extra_payments/:extra_id", to: "extra_payments#destroy", as: :extra_payment
    resources :payments, only: [ :new, :create, :edit, :update, :destroy ]
    resources :statement_imports, only: [ :new, :create ] do
      collection do
        post :confirm
      end
    end
  end
  resources :transfers, only: [ :index, :new, :create, :destroy ] do
    collection do
      get :quick_new
    end
  end
  resources :recurring_templates do
    member do
      post :process_transaction
      post :toggle_active
    end
  end

  resources :monthly_incomes, only: [ :index, :create, :update, :destroy ] do
    member do
      post :process_transaction
      patch :toggle_active
    end
  end

  resources :monthly_expenses, only: [ :index, :create, :update, :destroy ] do
    member do
      post :process_transaction
      patch :toggle_active
    end
  end
  resources :monthly_reports, only: [ :index, :show ]

  # Financial reports (overview, spending, debt, recurring, accounts, insights)
  scope :reports, as: :reports do
    get "/", to: "reports/overview#index", as: :overview
    get "/by_category", to: "reports/category_spending#index", as: :by_category
    get "/trends", to: "reports/spending_trend#index", as: :trends
    get "/budgets", to: "reports/budgets#index", as: :budgets
    get "/credit_cards", to: "reports/credit_cards#index", as: :credit_cards
    get "/loans", to: "reports/loans#index", as: :loans
    get "/recurring", to: "reports/recurring#index", as: :recurring
    get "/money_sources", to: "reports/money_sources#index", as: :money_sources
    get "/transfers", to: "reports/transfers#index", as: :transfers
    get "/insights", to: "reports/insights#index", as: :insights
    get "/transactions", to: "reports/transactions#index", as: :transactions
  end

  resources :imports, only: [ :new, :create ]

  # Gmail expense import
  get "settings/gmail", to: "gmail_connections#index", as: :gmail_connection
  patch "settings/gmail", to: "gmail_connections#update"
  delete "settings/gmail", to: "gmail_connections#destroy"
  post "settings/gmail/sync", to: "gmail_connections#sync", as: :sync_gmail_connection
  get "settings/gmail/sync_status", to: "gmail_connections#sync_status", as: :gmail_sync_status
  post "settings/gmail/setup_sync", to: "gmail_connections#setup_sync", as: :setup_sync_gmail_connection
  post "settings/gmail/auth/start", to: "gmail_connections#start_auth", as: :start_gmail_auth
  get "auth/google/callback", to: "gmail_connections#callback", as: :google_callback
  scope "gmail/reviews" do
    post ":id/approve", to: "gmail_connections#approve", as: :approve_gmail_review
    post ":id/reject", to: "gmail_connections#reject", as: :reject_gmail_review
  end

  # Spending alerts (notification center) and their settings
  resources :alerts, only: [ :index, :update ] do
    patch :mark_all_read, on: :collection
  end
  get "settings/alerts", to: "alert_settings#show", as: :alert_settings
  patch "settings/alerts", to: "alert_settings#update"

  # Settings → Día de pago (pay-cycle configuration)
  get "settings/pay", to: "pay_settings#show", as: :pay_settings
  patch "settings/pay", to: "pay_settings#update"

  # Expense ingestion playground (internal testing / debugging page)
  get "expense-playground", to: "expense_playground#show", as: :expense_playground
  post "expense-playground/process", to: "expense_playground#run", as: :expense_playground_process
  post "expense-playground/process_file", to: "expense_playground#process_file", as: :expense_playground_process_file
  post "expense-playground/batch_create", to: "expense_playground#batch_create", as: :expense_playground_batch_create
  post "expense-playground/create", to: "expense_playground#create", as: :expense_playground_create
  get "expense-playground/history", to: "expense_playground#history", as: :expense_playground_history
  get "expense-playground/ai_summary", to: "expense_playground#ai_summary", as: :expense_playground_ai_summary
  get "expense-evaluations", to: "expense_evaluations#index", as: :expense_evaluations
  post "expense-evaluations/start", to: "expense_evaluations#start", as: :expense_evaluations_start
  get "expense-evaluations/:id", to: "expense_evaluations#show", as: :expense_evaluation
  get "expense-evaluations/:id/cases", to: "expense_evaluations#cases", as: :expense_evaluation_cases
  post "expense-evaluations/:id/retry", to: "expense_evaluations#retry", as: :expense_evaluation_retry
  post "expense-evaluations/:id/cases/:case_id/map", to: "expense_evaluations#map_case", as: :expense_evaluation_map_case

  # Financial chat (real-time conversational assistant)
  get "financial_chat", to: "financial_chat#show", as: :financial_chat
  post "financial_chat/messages", to: "financial_chats/messages#create", as: :financial_chat_messages

  # Financial summary (month snapshot page)
  get "financial_summary", to: "financial_summary#show", as: :financial_summary

  # Día de Cuadre (reconciliation dashboard)
  get "reconciliation", to: "reconciliations#show", as: :reconciliation
  post "reconciliation/refresh", to: "reconciliations#refresh", as: :reconciliation_refresh
  get "reconciliation/search_expenses", to: "reconciliations#search_expenses", as: :reconciliation_search_expenses
  get "reconciliation/search_movements", to: "reconciliations#search_movements", as: :reconciliation_search_movements
  post "reconciliation/payments/:recurring_template_id/assign",
       to: "reconciliations#assign_payment", as: :reconciliation_assign_payment
  post "reconciliation/sources/:money_source_id/actual_balance",
       to: "reconciliations#set_actual_balance", as: :reconciliation_actual_balance
  post "reconciliation/sources/:money_source_id/leave_pending",
       to: "reconciliations#leave_pending", as: :reconciliation_leave_pending

  # Dashboard is the app's home
  root "dashboard#index"
  get "dashboard", to: "dashboard#index", as: :dashboard

  # Hybrid financial setup wizard
  get "financial_setup", to: "financial_setups#show", as: :financial_setup
  get "financial_setup/done", to: "financial_setups#done", as: :financial_setup_done
  post "financial_setup/select", to: "financial_setups#select", as: :financial_setup_select
  post "financial_setup/manual", to: "financial_setups#save_manual", as: :financial_setup_manual
  post "financial_setup/upload", to: "financial_setups#process_upload", as: :financial_setup_upload
  post "financial_setup/import_confirm", to: "financial_setups#import_confirm", as: :financial_setup_import_confirm
  post "financial_setup/complete", to: "financial_setups#complete", as: :financial_setup_complete
  post "financial_setup/dismiss", to: "financial_setups#dismiss", as: :financial_setup_dismiss
  post "financial_setup/reset", to: "financial_setups#reset", as: :financial_setup_reset
  get "financial_setup/step/:step", to: "financial_setups#step", as: :financial_setup_step
  get "financial_setup/step/:step/manual", to: "financial_setups#manual", as: :financial_setup_manual_screen
  get "financial_setup/step/:step/upload", to: "financial_setups#upload", as: :financial_setup_upload_screen
  get "financial_setup/step/:step/import_review", to: "financial_setups#import_review", as: :financial_setup_import_review
  get "financial_setup/step/:step/edit_all", to: "financial_setups#edit_all", as: :financial_setup_edit_all
  post "financial_setup/save_edits", to: "financial_setups#save_edits", as: :financial_setup_save_edits
  post "financial_setup/remove_source", to: "financial_setups#remove_source", as: :financial_setup_remove_source
end
