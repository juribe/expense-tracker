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
      post :parse
      post :bulk_create
    end
  end
  resources :incomes
  resources :categories
  resources :money_sources
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
end
