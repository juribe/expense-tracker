PaymentEngine::Engine.routes.draw do
  namespace :admin do
    root "dashboard#index"

    resources :membership_types do
      member { post :archive }
    end
    resources :payment_options

    resources :memberships do
      member do
        post :suspend
        post :reactivate
        post :extend
      end
    end

    resources :premium_identities, only: [ :index, :show ] do
      member { post :release }
    end

    resources :subscriptions do
      member do
        post :cancel
        post :resume
      end
    end

    resources :purchases, only: [:index, :show]
    resources :payments, only: [:index, :show] do
      member { post :refund }
    end

    resources :providers do
      member { post :test_connection }
    end

    resources :webhook_events, only: [:index, :show] do
      member { post :reprocess }
    end

    resource :settings, only: [:show, :update]
    get "settings/commercial", to: "settings#commercial", as: :commercial_settings
    patch "settings/commercial", to: "settings#update_commercial"
  end

  namespace :webhooks do
    post ":provider", to: "events#create"
  end
end
