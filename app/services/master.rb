# Master data (spec/api.md §5.2–5.6, §5.8; domain §3).
#
# Updates are full replacements: whatever the body omits becomes null or
# false. Uniqueness and foreign keys are enforced by the schema, and their
# violations surface as 409 and 422 through ApiError.from_database.
module Master
  ACCOUNT_TYPES = %w[asset liability equity revenue expense].freeze
  ACTIVITIES = %w[operating investing financing].freeze

  module_function

  def find(model, key, what) = model.find_by(model.primary_key => key) || raise(ApiError::NotFound, "#{what} not found")

  # -- Organizations ---------------------------------------------------------

  def organization_json(o)
    { "id" => o.id, "name" => o.name, "legal_name" => o.legal_name, "tax_id" => o.tax_id,
      "country_code" => o.country_code, "default_currency" => o.default_currency, "email" => o.email,
      "is_self" => o.is_self }
  end

  def organization_fields(b)
    { name: b.required_str("name"), legal_name: b.text("legal_name"), tax_id: b.text("tax_id"),
      country_code: b.text("country_code"), default_currency: b.text("default_currency"),
      email: b.text("email"), is_self: b.bool("is_self") }
  end

  def check_self(fields, id = nil)
    return unless fields[:is_self] && Organization.where(is_self: true).where.not(id:).exists?

    raise ApiError::Conflict, "another organization is already marked as our own"
  end

  def list_organizations = Organization.order(:name, :id).map { organization_json(_1) }
  def get_organization(id) = find(Organization, id, "organization")

  def create_organization(b)
    fields = organization_fields(b)
    check_self(fields)
    Organization.create!(fields).id
  end

  def update_organization(id, b)
    fields = organization_fields(b)
    get_organization(id)
    check_self(fields, id)
    Organization.where(id:).update_all(fields)
  end

  # -- Customers and suppliers -------------------------------------------------

  def customer_json(c)
    { "id" => c.id, "organization_id" => c.organization_id, "customer_number" => c.customer_number,
      "ar_account_id" => c.ar_account_id, "payment_terms_code" => c.payment_terms_code,
      "currency_code" => c.currency_code, "tax_code" => c.tax_code,
      "credit_limit" => Values.fmt4(c.credit_limit), "is_active" => c.is_active }
  end

  def supplier_json(s)
    { "id" => s.id, "organization_id" => s.organization_id, "supplier_number" => s.supplier_number,
      "ap_account_id" => s.ap_account_id, "payment_terms_code" => s.payment_terms_code,
      "currency_code" => s.currency_code, "tax_code" => s.tax_code, "is_active" => s.is_active }
  end

  def party_fields(b, number, control)
    { organization_id: b.required_id("organization_id"), number => b.text(number.to_s), control => b.int(control.to_s),
      payment_terms_code: b.text("payment_terms_code"), currency_code: b.text("currency_code"),
      tax_code: b.text("tax_code") }
  end

  def customer_fields(b)
    fields = party_fields(b, :customer_number, :ar_account_id)
    limit = b.decimal("credit_limit")
    raise ApiError::Unprocessable, "credit_limit must not be negative" if limit&.negative?

    fields.merge(credit_limit: limit)
  end

  def list_customers = Customer.order(:id).map { customer_json(_1) }
  def get_customer(id) = find(Customer, id, "customer")
  def create_customer(b) = Customer.create!(customer_fields(b)).id

  def update_customer(id, b)
    b.required_id("organization_id")
    get_customer(id)
    Customer.where(id:).update_all(customer_fields(b).merge(is_active: b.bool("is_active")))
  end

  def list_suppliers = Supplier.order(:id).map { supplier_json(_1) }
  def get_supplier(id) = find(Supplier, id, "supplier")
  def create_supplier(b) = Supplier.create!(party_fields(b, :supplier_number, :ap_account_id)).id

  def update_supplier(id, b)
    b.required_id("organization_id")
    get_supplier(id)
    fields = party_fields(b, :supplier_number, :ap_account_id)
    Supplier.where(id:).update_all(fields.merge(is_active: b.bool("is_active")))
  end

  # -- Products ----------------------------------------------------------------

  def product_json(p)
    { "id" => p.id, "sku" => p.sku, "name" => p.name, "description" => p.description,
      "unit_price" => Values.fmt4(p.unit_price), "currency_code" => p.currency_code,
      "revenue_account_id" => p.revenue_account_id, "tax_code" => p.tax_code,
      "track_inventory" => p.track_inventory, "inventory_account_id" => p.inventory_account_id,
      "cogs_account_id" => p.cogs_account_id, "is_active" => p.is_active }
  end

  def product_fields(b)
    { sku: b.required_str("sku"), name: b.required_str("name"), description: b.text("description"),
      unit_price: b.decimal("unit_price", default: Values::ZERO), currency_code: b.text("currency_code"),
      revenue_account_id: b.int("revenue_account_id"), tax_code: b.text("tax_code"),
      track_inventory: b.bool("track_inventory"), inventory_account_id: b.int("inventory_account_id"),
      cogs_account_id: b.int("cogs_account_id") }
  end

  def product_required(b)
    b.required_str("sku")
    b.required_str("name")
  end

  def list_products = Product.order(:sku, :id).map { product_json(_1) }
  def get_product(id) = find(Product, id, "product")

  def create_product(b)
    product_required(b)
    Product.create!(product_fields(b)).id
  end

  def update_product(id, b)
    product_required(b)
    get_product(id)
    Product.where(id:).update_all(product_fields(b).merge(is_active: b.bool("is_active")))
  end

  # -- Chart of accounts -------------------------------------------------------

  def account_json(a)
    { "id" => a.id, "code" => a.code, "name" => a.name, "account_type" => a.account_type,
      "parent_id" => a.parent_id, "currency_code" => a.currency_code, "is_postable" => a.is_postable,
      "is_active" => a.is_active, "is_cash" => a.is_cash, "cash_flow_activity" => a.cash_flow_activity }
  end

  def account_required(b)
    b.required_str("code")
    b.required_str("name")
    b.required_str("account_type")
  end

  def account_fields(b, id = nil)
    fields = { code: b.required_str("code"), name: b.required_str("name"), account_type: b.required_str("account_type"),
               parent_id: b.int("parent_id"), currency_code: b.text("currency_code"),
               is_postable: b.bool("is_postable"), is_cash: b.bool("is_cash"),
               cash_flow_activity: b.text("cash_flow_activity") || "operating" }
    unless ACCOUNT_TYPES.include?(fields[:account_type])
      raise ApiError::Unprocessable, "account_type must be one of #{ACCOUNT_TYPES.join(', ')}"
    end
    unless ACTIVITIES.include?(fields[:cash_flow_activity])
      raise ApiError::Unprocessable, "cash_flow_activity must be one of #{ACTIVITIES.join(', ')}"
    end
    if fields[:is_cash] && fields[:account_type] != "asset"
      raise ApiError::Unprocessable, "only an asset account can be a cash account"
    end
    if (parent = fields[:parent_id])
      raise ApiError::Unprocessable, "an account cannot be its own parent" if parent == id
      raise ApiError::Unprocessable, "unknown parent_id" unless Account.exists?(parent)
    end
    fields
  end

  def list_accounts = Account.order(:code, :id).map { account_json(_1) }
  def get_account(id) = find(Account, id, "account")

  def create_account(b)
    account_required(b)
    Account.create!(account_fields(b)).id
  end

  def update_account(id, b)
    account_required(b)
    get_account(id)
    Account.where(id:).update_all(account_fields(b, id).merge(is_active: b.bool("is_active")))
  end

  # -- Tax codes, payment terms, warehouses -----------------------------------

  def tax_code_json(t)
    { "code" => t.code, "name" => t.name, "rate" => Values.fmt4(t.rate), "tax_account_id" => t.tax_account_id,
      "is_active" => t.is_active }
  end

  def tax_code_fields(b)
    rate = b.decimal("rate", Values::RATE, default: Values::ZERO)
    raise ApiError::Unprocessable, "rate must not be negative" if rate.negative?

    { name: b.required_str("name"), rate:, tax_account_id: b.int("tax_account_id") }
  end

  def list_tax_codes = TaxCode.order(:code).map { tax_code_json(_1) }
  def get_tax_code(code) = find(TaxCode, code, "tax code")

  def create_tax_code(b)
    code = b.required_str("code")
    b.required_str("name")
    fields = tax_code_fields(b)
    raise ApiError::Conflict, "tax code already exists" if TaxCode.exists?(code)

    TaxCode.create!(fields.merge(code:))
    code
  end

  def update_tax_code(code, b)
    b.required_str("name")
    get_tax_code(code)
    TaxCode.where(code:).update_all(tax_code_fields(b).merge(is_active: b.bool("is_active")))
  end

  def payment_term_json(p) = { "code" => p.code, "name" => p.name, "due_days" => p.due_days }

  def due_days(b)
    days = b.int("due_days") || 0
    raise ApiError::Unprocessable, "due_days must not be negative" if days.negative?

    days
  end

  def list_payment_terms = PaymentTerm.order(:due_days, :code).map { payment_term_json(_1) }
  def get_payment_term(code) = find(PaymentTerm, code, "payment term")

  def create_payment_term(b)
    code = b.required_str("code")
    name = b.required_str("name")
    days = due_days(b)
    raise ApiError::Conflict, "payment term already exists" if PaymentTerm.exists?(code)

    PaymentTerm.create!(code:, name:, due_days: days)
    code
  end

  def update_payment_term(code, b)
    name = b.required_str("name")
    get_payment_term(code)
    PaymentTerm.where(code:).update_all(name:, due_days: due_days(b))
  end

  def warehouse_json(w)
    { "id" => w.id, "code" => w.code, "name" => w.name, "address_id" => w.address_id, "is_active" => w.is_active }
  end

  def warehouse_fields(b) = { code: b.required_str("code"), name: b.required_str("name"), address_id: b.int("address_id") }

  def list_warehouses = Warehouse.order(:code, :id).map { warehouse_json(_1) }
  def get_warehouse(id) = find(Warehouse, id, "warehouse")
  def create_warehouse(b) = Warehouse.create!(warehouse_fields(b)).id

  def update_warehouse(id, b)
    fields = warehouse_fields(b)
    get_warehouse(id)
    Warehouse.where(id:).update_all(fields.merge(is_active: b.bool("is_active")))
  end

  # -- Ledger settings and exchange rates -------------------------------------

  def settings_json(s) = { "base_currency" => s.base_currency, "fx_gain_loss_account_id" => s.fx_gain_loss_account_id }

  def currency(code, name = "currency_code")
    code = code.strip.upcase
    unless code.match?(/\A[A-Z]{3}\z/) && Currency.exists?(code)
      raise ApiError::Unprocessable, "unknown #{name}"
    end

    code
  end

  def update_settings(b)
    base = currency(b.required_str("base_currency"), "base_currency")
    fx = b.int("fx_gain_loss_account_id")
    if fx && !Account.exists?(id: fx, is_postable: true, is_active: true)
      raise ApiError::Unprocessable, "fx_gain_loss_account_id must be a postable, active account"
    end
    current = GlSetting.lock.find(1)
    if base != current.base_currency && JournalEntry.exists?
      raise ApiError::Unprocessable, "the base currency cannot change once journal entries exist"
    end

    GlSetting.where(id: 1).update_all(base_currency: base, fx_gain_loss_account_id: fx)
  end

  def exchange_rate_json(r)
    { "currency_code" => r.currency_code, "rate_date" => Values.fmt_date(r.rate_date), "rate" => Values.fmt_rate(r.rate) }
  end

  def list_exchange_rates = ExchangeRate.order(:currency_code, rate_date: :desc).map { exchange_rate_json(_1) }

  def rate(b)
    rate = b.decimal("rate", Values::FX)
    raise ApiError::BadRequest, "rate is required" if rate.nil?
    raise ApiError::Unprocessable, "rate must be greater than 0" unless rate.positive?

    rate
  end

  def create_exchange_rate(b)
    code = b.required_str("currency_code")
    date = b.required_str("rate_date")
    raise ApiError::BadRequest, "rate is required" if b.str("rate").blank?

    code = currency(code)
    date = Values.parse_date(date, "rate_date")
    r = rate(b)
    if ExchangeRate.exists?(currency_code: code, rate_date: date)
      raise ApiError::Conflict, "a rate for that currency and date already exists"
    end

    ExchangeRate.create!(currency_code: code, rate_date: date, rate: r)
    { "currency_code" => code, "rate_date" => date.iso8601 }
  end

  def rate_key(code, date)
    rows = ExchangeRate.where(currency_code: code.strip.upcase,
                              rate_date: Values.parse_date(date, "rate_date", error: ApiError::BadRequest))
    raise ApiError::NotFound, "exchange rate not found" unless rows.exists?

    rows
  end

  def get_exchange_rate(code, date) = rate_key(code, date).first
  def update_exchange_rate(code, date, b) = rate_key(code, date).update_all(rate: rate(b))
  def delete_exchange_rate(code, date) = rate_key(code, date).delete_all
end
