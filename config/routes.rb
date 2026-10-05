Rails.application.routes.draw do
  get "healthz", to: "health#healthz"
  get "readyz", to: "health#readyz"

  # The JSON API (spec/api.md §5). Ids are validated by the controllers, so
  # a malformed one is a 400 rather than an unrouted 404.
  scope "api", module: "api", as: "api", format: false,
               constraints: { id: %r{[^/]+}, currency: %r{[^/]+}, date: %r{[^/]+} } do
    post "auth/login", to: "auth#login"
    post "auth/logout", to: "auth#logout"
    get "auth/me", to: "auth#me"

    get "users", to: "users#index"
    post "users", to: "users#create"
    get "users/:id", to: "users#show"
    put "users/:id", to: "users#update"
    post "users/:id/password", to: "users#password"

    Api::MasterDataController::COLLECTIONS.each_key do |c|
      scope c, defaults: { collection: c } do
        get "", to: "master_data#index"
        post "", to: "master_data#create"
        get ":id", to: "master_data#show"
        put ":id", to: "master_data#update"
      end
    end
    get "accounts/:id/ledger", to: "reports#ledger"
    post "fiscal-years/:id/close", to: "fiscal_years#close"
    post "fiscal-years/:id/reopen", to: "fiscal_years#reopen"

    get "settings", to: "settings#show"
    put "settings", to: "settings#update"
    get "exchange-rates", to: "settings#rates"
    post "exchange-rates", to: "settings#create_rate"
    put "exchange-rates/:currency/:date", to: "settings#update_rate"
    delete "exchange-rates/:currency/:date", to: "settings#delete_rate"

    {
      "documents" => Kinds::DOCUMENTS.keys,
      "payments" => Kinds::PAYMENTS.keys,
      "orders" => Kinds::ORDERS.keys,
    }.each do |controller, collections|
      collections.each do |c|
        scope c, controller:, defaults: { collection: c } do
          get "", action: :index
          post "", action: :create
          get ":id", action: :show
          put ":id", action: :update
          delete ":id", action: :destroy
          get ":id/lines", action: :lines unless controller == "payments"
          if controller == "orders"
            %w[confirm close cancel].each { |t| post ":id/#{t}", action: :transition, defaults: { transition: t } }
            kind = Kinds::ORDERS[c]
            post ":id/#{kind.bill_verb}", action: :bill
            post ":id/#{kind.move_verb}", action: :move
          else
            post ":id/post", action: :post
            post ":id/unpost", action: :unpost
          end
          if controller == "payments" || (controller == "documents" && Kinds::DOCUMENTS[c].credit)
            get ":id/applications", action: :applications
            post ":id/apply", action: :apply
          end
        end
      end
    end

    Kinds.printable.each_key do |c|
      get "#{c}/:id/pdf", to: "printing#pdf", defaults: { collection: c }
      post "#{c}/:id/email", to: "printing#email", defaults: { collection: c }
    end

    scope "stock-movements", controller: :stock_movements do
      get "", action: :index
      post "", action: :create
      get ":id", action: :show
      put ":id", action: :update
      delete ":id", action: :destroy
      post ":id/post", action: :post
      post ":id/unpost", action: :unpost
    end

    scope "bank-statements", controller: :bank_statements do
      get "", action: :index
      post "", action: :create
      get ":id", action: :show
      put ":id", action: :update
      delete ":id", action: :destroy
      get ":id/lines", action: :lines
      post ":id/lines", action: :add_line
      post ":id/import", action: :import
      get ":id/candidates", action: :candidates
      post ":id/auto-match", action: :auto_match
      post ":id/reconcile", action: :reconcile
      post ":id/reopen", action: :reopen
    end
    post "bank-statement-lines/:id/match", to: "bank_statements#match"
    post "bank-statement-lines/:id/unmatch", to: "bank_statements#unmatch"
    delete "bank-statement-lines/:id", to: "bank_statements#delete_line"

    get "journal-entries/:id", to: "reports#journal_entry"
    get "trial-balance", to: "reports#trial_balance"
    get "profit-and-loss", to: "reports#profit_and_loss"
    get "balance-sheet", to: "reports#balance_sheet"
    get "cash-flow", to: "reports#cash_flow"
    get "ar-aging", to: "reports#ar_aging"
    get "ap-aging", to: "reports#ap_aging"
    get "inventory-valuation", to: "reports#inventory_valuation"

    match "*path", to: "base#not_found", via: :all
    match "", to: "base#not_found", via: :all
  end

  # The server-rendered UI (domain §13). Forms GET to show and POST to save.
  scope module: "ui", format: false, constraints: { id: /\d+/, line: /\d+/ } do
    root "home#show"
    get "login", to: "sessions#new", as: :login
    post "login", to: "sessions#create"
    post "logout", to: "sessions#destroy"

    Ui::MasterDataController::COLLECTIONS.each_key do |c|
      scope c, controller: :master_data, defaults: { collection: c } do
        get "", action: :index
        match "new", action: :new, via: %i[get post]
        match ":id", action: :edit, via: %i[get post], constraints: { id: %r{[^/]+} }
      end
    end

    get "users", to: "users#index"
    match "users/new", to: "users#new", via: %i[get post]
    match "users/:id", to: "users#edit", via: %i[get post]
    match "users/:id/password", to: "users#password", via: %i[get post]
    match "settings", to: "settings#show", via: %i[get post]

    { "documents" => Kinds::DOCUMENTS, "payments" => Kinds::PAYMENTS, "orders" => Kinds::ORDERS }.each do |controller, kinds|
      kinds.each do |c, kind|
        scope c, controller:, defaults: { collection: c } do
          get "", action: :index
          match "new", action: :new, via: %i[get post]
          get ":id", action: :show
          match ":id/edit", action: :edit, via: %i[get post]
          match ":id/delete", action: :destroy, via: %i[get post]
          if controller == "orders"
            %w[confirm close cancel].each { |t| match ":id/#{t}", action: :transition, via: %i[get post], defaults: { transition: t } }
            match ":id/#{kind.bill_verb}", action: :bill, via: %i[get post]
            match ":id/#{kind.move_verb}", action: :move, via: %i[get post]
          else
            match ":id/post", action: :post, via: %i[get post]
            match ":id/unpost", action: :unpost, via: %i[get post]
            match ":id/apply", action: :apply, via: %i[get post]
          end
          match ":id/email", action: :email, via: %i[get post] unless controller == "payments"
        end
      end
    end

    scope "stock-movements", controller: :stock_movements do
      get "", action: :index
      match "new", action: :new, via: %i[get post]
      get ":id", action: :show
      match ":id/edit", action: :edit, via: %i[get post]
      match ":id/delete", action: :destroy, via: %i[get post]
      match ":id/post", action: :post, via: %i[get post]
      match ":id/unpost", action: :unpost, via: %i[get post]
    end

    scope "reports", controller: :reports do
      get "profit-and-loss", action: :profit_and_loss
      get "balance-sheet", action: :balance_sheet
      get "cash-flow", action: :cash_flow
      get "trial-balance", action: :trial_balance
      get "ar-aging", action: :ar_aging
      get "ap-aging", action: :ap_aging
    end
    get "inventory-valuation", to: "reports#inventory_valuation"
    get "accounts/:id/ledger", to: "reports#ledger"
    get "journal-entries/:id", to: "reports#journal_entry"

    get "periods", to: "periods#index"
    match "fiscal-years/new", to: "periods#new_year", via: %i[get post]
    match "fiscal-years/:id", to: "periods#edit_year", via: %i[get post]
    match "fiscal-years/:id/close", to: "periods#close_year", via: %i[get post]
    post "fiscal-years/:id/reopen", to: "periods#reopen_year"
    match "accounting-periods/new", to: "periods#new_period", via: %i[get post]
    match "accounting-periods/:id", to: "periods#edit_period", via: %i[get post]
    post "accounting-periods/:id/toggle", to: "periods#toggle"

    get "exchange-rates", to: "exchange_rates#index"
    match "exchange-rates/new", to: "exchange_rates#new", via: %i[get post]
    match "exchange-rates/:currency/:date", to: "exchange_rates#edit", via: %i[get post]
    match "exchange-rates/:currency/:date/delete", to: "exchange_rates#destroy", via: %i[get post]

    scope "bank-statements", controller: :bank_statements do
      get "", action: :index
      match "new", action: :new, via: %i[get post]
      get ":id", action: :show
      match ":id/edit", action: :edit, via: %i[get post]
      match ":id/delete", action: :destroy, via: %i[get post]
      post ":id/lines", action: :add_line
      post ":id/import", action: :import
      post ":id/auto-match", action: :auto_match
      post ":id/reconcile", action: :reconcile
      post ":id/reopen", action: :reopen
      post ":id/lines/:line/match", action: :match
      post ":id/lines/:line/unmatch", action: :unmatch
      post ":id/lines/:line/delete", action: :delete_line
    end

    match "*path", to: "base#not_found", via: :all
  end
end
