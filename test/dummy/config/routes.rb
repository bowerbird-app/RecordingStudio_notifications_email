Rails.application.routes.draw do
  if Rails.env.development?
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  devise_for :users

  # RecordingStudio engine is data/API-focused and has no browser root route.
  # Keep legacy links working by redirecting the base path to the app home.
  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioCommentable::Engine, at: "/commentable"
  mount RecordingStudioNotifications::Engine, at: "/recording_studio_notifications"
  mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"

  scope module: :recording_studio_commentable do
    resources :recordings, only: [] do
      resources :comments, only: %i[index new create edit update destroy] do
        collection do
          get :all, path: "all"
        end
      end
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  get "docs/install", to: "docs#install", as: :docs_install
  get "docs/config", to: "docs#configuration", as: :docs_config
  get "docs/recordable_types", to: "docs#recordable_types", as: :docs_recordable_types
  get "docs/recordings_tree", to: "docs#recordings_tree", as: :docs_recordings_tree
  get "docs/gem_views", to: "docs#gem_views", as: :docs_gem_views
  get "docs/methods", to: "docs#methods", as: :docs_methods
    get "docs/webhook_lab", to: "docs#webhook_lab", as: :docs_webhook_lab
    post "docs/webhook_lab/create_notification", to: "docs#create_webhook_lab_notification",
      as: :create_docs_webhook_lab_notification
    post "docs/webhook_lab/fire_event", to: "docs#fire_webhook_lab_event",
      as: :fire_docs_webhook_lab_event

  resources :pages, only: [:index, :create]
  resource :system_notifications, only: [:new, :create]

  # Defines the root path route ("/")
  root "home#index"
end
