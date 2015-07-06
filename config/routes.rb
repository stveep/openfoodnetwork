Openfoodnetwork::Application.routes.draw do
  root :to => 'home#index'

  # Redirects from old URLs avoid server errors and helps search engines
  get "/enterprises", to: redirect("/")
  get "/products", to: redirect("/")
  get "/t/products/:id", to: redirect("/")

  get "/#/login", to: "home#index", as: :spree_login
  get "/login", to: redirect("/#/login")

  get "/map", to: "map#index", as: :map

  get "/register", to: "registration#index", as: :registration
  get "/register/auth", to: "registration#authenticate", as: :registration_auth

  resource :shop, controller: "shop" do
    get :products
    post :order_cycle
    get :order_cycle
  end

  resources :producers, only: [:index] do
    collection do
      get :signup
    end
  end

  resources :shops, only: [:index] do
    collection do
      get :signup
    end
  end

  resources :groups, only: [:index, :show] do
    collection do
      get :signup
    end
  end

  get '/checkout', :to => 'checkout#edit' , :as => :checkout
  put '/checkout', :to => 'checkout#update' , :as => :update_checkout
  get '/checkout/paypal_payment/:order_id', to: 'checkout#paypal_payment', as: :paypal_payment

  resources :enterprises do
    collection do
      get :suppliers
      get :distributors
      post :search
      get :check_permalink
    end

    member do
      get :shop_front # new world
      get :shop # old world
    end
  end
  get '/:id/shop', to: 'enterprises#shop', as: 'enterprise_shop'

  devise_for :enterprise, controllers: { confirmations: 'enterprise_confirmations' }

  namespace :admin do
    resources :order_cycles do
      post :bulk_update, on: :collection, as: :bulk_update
      get :clone, on: :member
    end

    resources :enterprises do
      collection do
        get :for_order_cycle
        post :bulk_update, as: :bulk_update
      end

      member do
        get :welcome
        put :register
      end

      resources :producer_properties do
        post :update_positions, on: :collection
      end
    end

    resources :enterprise_relationships
    resources :enterprise_roles

    resources :enterprise_fees do
      collection do
        get :for_order_cycle
        post :bulk_update, :as => :bulk_update
      end
    end

    resources :enterprise_groups do
      get :move_up
      get :move_down
    end

    resources :variant_overrides do
      post :bulk_update, on: :collection
    end

    resources :customers, only: [:index, :update]

    resource :content
  end

  namespace :api do
    resources :enterprises do
      post :update_image, on: :member
      get :managed, on: :collection
      get :accessible, on: :collection
    end
    resources :order_cycles do
      get :managed, on: :collection
      get :accessible, on: :collection
    end
  end

  get "about_us", :controller => 'home', :action => "about_us"

  namespace :open_food_network do
    resources :cart do
      post :add_variant
    end
  end

  # Mount Spree's routes
  mount Spree::Core::Engine, :at => '/'

end


# Overriding Devise routes to use our own controller
Spree::Core::Engine.routes.draw do
  devise_for :spree_user,
             :class_name => 'Spree::User',
             :controllers => { :sessions => 'spree/user_sessions',
                               :registrations => 'user_registrations',
                               :passwords => 'user_passwords' },
             :skip => [:unlocks, :omniauth_callbacks],
             :path_names => { :sign_out => 'logout' },
             :path_prefix => :user
end



Spree::Core::Engine.routes.prepend do
  match '/admin/reports/orders_and_distributors' => 'admin/reports#orders_and_distributors', :as => "orders_and_distributors_admin_reports",  :via  => [:get, :post]
  match '/admin/reports/order_cycle_management' => 'admin/reports#order_cycle_management', :as => "order_cycle_management_admin_reports",  :via  => [:get, :post]
  match '/admin/reports/group_buys' => 'admin/reports#group_buys', :as => "group_buys_admin_reports",  :via  => [:get, :post]
  match '/admin/reports/bulk_coop' => 'admin/reports#bulk_coop', :as => "bulk_coop_admin_reports",  :via  => [:get, :post]
  match '/admin/reports/payments' => 'admin/reports#payments', :as => "payments_admin_reports",  :via  => [:get, :post]
  match '/admin/reports/orders_and_fulfillment' => 'admin/reports#orders_and_fulfillment', :as => "orders_and_fulfillment_admin_reports",  :via  => [:get, :post]
  match '/admin/reports/users_and_enterprises' => 'admin/reports#users_and_enterprises', :as => "users_and_enterprises_admin_reports",  :via => [:get, :post]
  match '/admin/reports/sales_tax' => 'admin/reports#sales_tax', :as => "sales_tax_admin_reports",  :via  => [:get, :post]
  match '/admin/products/bulk_edit' => 'admin/products#bulk_edit', :as => "bulk_edit_admin_products"
  match '/admin/orders/bulk_management' => 'admin/orders#bulk_management', :as => "admin_bulk_order_management"
  match '/admin/reports/products_and_inventory' => 'admin/reports#products_and_inventory', :as => "products_and_inventory_admin_reports",  :via  => [:get, :post]
  match '/admin/reports/customers' => 'admin/reports#customers', :as => "customers_admin_reports",  :via  => [:get, :post]
  match '/admin/reports/xero_invoices' => 'admin/reports#xero_invoices', :as => "xero_invoices_admin_reports",  :via  => [:get, :post]
  match '/admin', :to => 'admin/overview#index', :as => :admin
  match '/admin/payment_methods/show_provider_preferences' => 'admin/payment_methods#show_provider_preferences', :via => :get


  namespace :api, :defaults => { :format => 'json' } do
    resources :users do
      get :authorise_api, on: :collection
    end

    resources :products do
      collection do
        get :managed
        get :bulk_products
        get :overridable
      end
      delete :soft_delete

      resources :variants do
        delete :soft_delete
      end
    end

    resources :orders do
      get :managed, on: :collection
    end
  end

  namespace :admin do
    get '/search/known_users' => "search#known_users", :as => :search_known_users

    resources :products do
      get :product_distributions, on: :member

      post :bulk_update, :on => :collection, :as => :bulk_update
    end

    resources :orders do
      get :managed, on: :collection
    end
  end

  resources :orders do
    get :clear, :on => :collection
    get :order_cycle_expired, :on => :collection
  end

end
