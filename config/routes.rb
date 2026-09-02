Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Devise authentication
  devise_for :users, controllers: {
    registrations: 'users/registrations',
    passwords: 'users/passwords'
  }

  # Allow sign out via GET as a no-JS fallback (Turbo/JS may not be loaded)
  devise_scope :user do
    get "users/sign_out", to: "devise/sessions#destroy", as: :user_session_sign_out_get
  end

  # QA Validation routes
  get 'qa/validate', to: 'qa_validate_dashboard_reports#index'
  get 'qa/validate/dashboard', to: 'qa_validate_dashboard_reports#dashboard'
  get 'qa/validate/reports', to: 'qa_validate_dashboard_reports#reports'
  get 'qa/validate/run_all', to: 'qa_validate_dashboard_reports#run_all'

  # Resources
  resources :expenses do
    collection do
      delete :bulk_destroy
      patch :bulk_update
      post :parse
      post :bulk_create
    end
  end
  resources :incomes
  resources :categories
  get "money_sources/cash",         to: "money_sources#index", as: :money_sources_cash, defaults: { type: "cash" }
  get "money_sources/credit_cards", to: "money_sources#index", as: :money_sources_credit_cards, defaults: { type: "credit_cards" }
  get "money_sources/loans",        to: "money_sources#index", as: :money_sources_loans, defaults: { type: "loans" }
  # Source Recognition prototype (static markup with fake data)
  get "money_sources/recognition", to: "money_sources#recognition", as: :money_sources_recognition
  resources :money_sources, id: /[0-9]+/
  resources :transfers, only: [ :index, :new, :create, :destroy ]
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
  resources :monthly_reports, only: [:index, :show]

  resources :imports, only: [:new, :create]

  # Gmail expense import
  get "settings/gmail", to: "gmail_connections#index", as: :gmail_connection
  patch "settings/gmail", to: "gmail_connections#update"
  delete "settings/gmail", to: "gmail_connections#destroy"
  post "settings/gmail/sync", to: "gmail_connections#sync", as: :sync_gmail_connection
  post "settings/gmail/auth/start", to: "gmail_connections#start_auth", as: :start_gmail_auth
  get "auth/google/callback", to: "gmail_connections#callback", as: :google_callback
  scope "gmail/reviews" do
    post ":id/approve", to: "gmail_connections#approve", as: :approve_gmail_review
    post ":id/reject", to: "gmail_connections#reject", as: :reject_gmail_review
  end

  # Categories as the main entry point
  get 'dashboard', to: 'dashboard#index'
  root to: 'categories#index'

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
