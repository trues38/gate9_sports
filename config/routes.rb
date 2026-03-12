Rails.application.routes.draw do
  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Root → Basketball Schedule (main product)
  root to: redirect("/basketball/schedule")

  # Waitlist subscription
  post "subscribe", to: "home#subscribe", as: :subscribe_home

  # Public performance transparency dashboard
  get "performance", to: "performance#index", as: :performance

  # Promax UI (A/B Test)
  get "promax", to: "promax#index"
  get "promax/:sport", to: "promax#index", as: :promax_sport


  # Authentication
  get "sign_in", to: "sessions#new"
  post "sign_in", to: "sessions#create"
  delete "sign_out", to: "sessions#destroy"
  get "sign_up", to: "registrations#new"
  post "sign_up", to: "registrations#create"

  # Subscriptions
  resources :subscriptions, only: [:new, :create, :show] do
    post :grant, on: :collection  # 관리자용
  end

  # Main tabs
  get "profile", to: "profile#index"

  # Admin namespace (must be before sport-scoped routes!)
  namespace :admin do
    # Auth
    get "login", to: "sessions#new", as: :login
    post "login", to: "sessions#create"
    delete "logout", to: "sessions#destroy", as: :logout

    resources :sports
    resources :subscriptions, only: [:index] do
      member do
        post :approve
        post :reject
      end
    end
    resources :reports do
      member do
        post :publish
        post :create_media
      end
    end
    resources :insights
    resources :games, only: [:index, :show]

    # ROE-2 YouTube Insights
    resources :roe2, only: [:index, :new, :create] do
      collection do
        post :extract
        post :analyze
      end
    end

    # Stats / Performance tracking
    get "stats", to: "stats#index"
    post "stats/record/:id", to: "stats#record_result", as: :record_result
    post "stats/sync", to: "stats#bulk_sync_results", as: :bulk_sync_results
  end

  # API namespace (g9-agent → DB 연결)
  namespace :api do
    resources :games, only: [:index, :show]
    resources :reports, only: [:index, :show, :create] do
      member do
        patch 'result', action: :record_result
      end
    end
    resources :social_contents, only: [:create]
  end

  # Sport-scoped resources (after admin to avoid conflicts)
  scope "/:sport", defaults: { sport: "basketball" }, constraints: { sport: /basketball|baseball|soccer|football|hockey/ } do
    resources :reports, only: [:index, :show]
    resources :insights, only: [:index, :show]
    resources :schedule, only: [:index], as: :schedule_index
    get "schedule/team/:team", to: "schedule#team", as: :schedule_team
    get "/", to: "schedule#index", as: :sport_home
  end
end
