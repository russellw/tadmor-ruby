module Ui
  # Master data screens (domain §13.3, M1–M6): a list and a form for each
  # collection, chosen by the route. Master data has no delete; every record
  # with is_active is deactivated through its form.
  class MasterDataController < BaseController
    C = Choices
    ACTIVE = Field.of("is_active", "Active", "bool")

    def self.party_fields(number, control, control_label, credit_limit: false)
      lambda do |record|
        fields = [
          Field.of("organization_id", "Organization", "ref", C.organizations, required: true, readonly_on_edit: true),
          Field.of(number, "Number"),
          Field.of(control, control_label, "ref", C.postable_accounts,
                   help: "The control account its documents post to; posting needs it."),
          Field.of("payment_terms_code", "Payment terms", "select", C.payment_terms),
          Field.of("currency_code", "Currency", "select", C.currencies),
          Field.of("tax_code", "Default tax code", "select", C.tax_codes),
        ]
        fields << Field.of("credit_limit", "Credit limit", "decimal") if credit_limit
        record ? fields + [ACTIVE] : fields
      end
    end

    def self.with_active(fields) = ->(record) { record ? fields + [ACTIVE] : fields }

    def self.account_fields(record)
      own = record && record["id"]
      parents = -> { C.accounts.call.reject { |v, _| v == own } } # M4: never the account itself
      fields = [
        Field.of("code", "Code", required: true),
        Field.of("name", "Name", required: true),
        Field.of("account_type", "Type", "select", C.static(*Master::ACCOUNT_TYPES.map { [_1, _1.capitalize] }), required: true),
        Field.of("parent_id", "Parent", "ref", parents),
        Field.of("currency_code", "Currency", "select", C.currencies),
        Field.of("is_postable", "Postable (unticked makes a summary account)", "bool"),
        Field.of("is_cash", "Cash account (assets only)", "bool"),
        Field.of("cash_flow_activity", "Cash-flow activity", "select", C.static(*Master::ACTIVITIES.map { [_1, _1.capitalize] })),
      ]
      record ? fields + [ACTIVE] : fields
    end

    Collection = Data.define(:title, :singular, :list, :columns, :fields, :get, :create, :update, :by_code, :keep)

    def self.collection(title, singular, list, columns, fields, get, create, update, by_code: false, keep: [])
      Collection.new(title, singular, list, columns, fields, get, create, update, by_code, keep)
    end

    ORG_NAMES = -> { Organization.pluck(:id, :name).to_h }
    WITH_ORG = ->(rows) { names = ORG_NAMES.call; rows.each { _1["organization_name"] = names[_1["organization_id"]] } }

    COLLECTIONS = {
      # M1
      "organizations" => collection(
        "Organizations", "organization", -> { Master.list_organizations },
        [Column.of("Name", "name"), Column.of("Legal name", "legal_name"), Column.of("Tax ID", "tax_id"),
         Column.of("Country", "country_code"), Column.of("Currency", "default_currency"),
         Column.of("Own company", "is_self", kind: "bool")],
        ->(_) {
          [Field.of("name", "Name", required: true), Field.of("legal_name", "Legal name"), Field.of("tax_id", "Tax ID"),
           Field.of("country_code", "Country", "select", C.countries),
           Field.of("default_currency", "Default currency", "select", C.currencies),
           Field.of("email", "Email", "email", help: "Documents are emailed here unless another recipient is given."),
           Field.of("is_self", "This is our own company (shown as the issuer on printed documents)", "bool")]
        },
        ->(id) { Master.organization_json(Master.get_organization(id)) }, :create_organization, :update_organization
      ),
      # M2
      "customers" => collection(
        "Customers", "customer", -> { WITH_ORG.call(Master.list_customers) },
        [Column.of("Organization", "organization_name"), Column.of("Number", "customer_number"),
         Column.of("Currency", "currency_code"), Column.of("Tax code", "tax_code"),
         Column.of("Terms", "payment_terms_code"), Column.of("Credit limit", "credit_limit", numeric: true, kind: "amount"),
         Column.of("Status", "is_active", kind: "active")],
        party_fields("customer_number", "ar_account_id", "A/R account", credit_limit: true),
        ->(id) { Master.customer_json(Master.get_customer(id)) }, :create_customer, :update_customer
      ),
      "suppliers" => collection(
        "Suppliers", "supplier", -> { WITH_ORG.call(Master.list_suppliers) },
        [Column.of("Organization", "organization_name"), Column.of("Number", "supplier_number"),
         Column.of("Currency", "currency_code"), Column.of("Tax code", "tax_code"),
         Column.of("Terms", "payment_terms_code"), Column.of("Status", "is_active", kind: "active")],
        party_fields("supplier_number", "ap_account_id", "A/P account"),
        ->(id) { Master.supplier_json(Master.get_supplier(id)) }, :create_supplier, :update_supplier
      ),
      # M3
      "products" => collection(
        "Products", "product", -> { Master.list_products },
        [Column.of("SKU", "sku"), Column.of("Name", "name"), Column.of("Unit price", "unit_price", numeric: true, kind: "amount"),
         Column.of("Currency", "currency_code"), Column.of("Tax code", "tax_code"),
         Column.of("Inventory", "track_inventory", kind: "bool"), Column.of("Status", "is_active", kind: "active")],
        with_active([
          Field.of("sku", "SKU", required: true), Field.of("name", "Name", required: true),
          Field.of("description", "Description", "textarea"), Field.of("unit_price", "Unit price", "decimal"),
          Field.of("currency_code", "Currency", "select", C.currencies), Field.of("tax_code", "Tax code", "select", C.tax_codes),
          Field.of("revenue_account_id", "Revenue account", "ref", C.postable_accounts,
                   help: "Used by invoice and credit-note lines that name no account."),
          Field.of("track_inventory", "Track inventory", "bool"),
          Field.of("inventory_account_id", "Inventory account", "ref", C.postable_accounts,
                   help: "Stock postings use it; bill lines that name no account are expensed to it."),
          Field.of("cogs_account_id", "COGS account", "ref", C.postable_accounts),
        ]),
        ->(id) { Master.product_json(Master.get_product(id)) }, :create_product, :update_product
      ),
      # M4
      "accounts" => collection(
        "Chart of accounts", "account", -> { Master.list_accounts },
        [Column.of("Code", "code"), Column.of("Name", "name"), Column.of("Type", "account_type", kind: "status"),
         Column.of("Currency", "currency_code"), Column.of("Postable", "is_postable", kind: "bool"),
         Column.of("Cash", "is_cash", kind: "bool"), Column.of("Status", "is_active", kind: "active")],
        method(:account_fields), ->(id) { Master.account_json(Master.get_account(id)) }, :create_account, :update_account
      ),
      # M5
      "tax-codes" => collection(
        "Tax codes", "tax code", -> { Master.list_tax_codes },
        [Column.of("Code", "code"), Column.of("Name", "name"), Column.of("Rate %", "rate", numeric: true, kind: "qty"),
         Column.of("Status", "is_active", kind: "active")],
        with_active([
          Field.of("code", "Code", required: true, readonly_on_edit: true), Field.of("name", "Name", required: true),
          Field.of("rate", "Rate (percent)", "decimal"),
          Field.of("tax_account_id", "Tax account", "ref", C.postable_accounts,
                   help: "Taxed lines post here; without one, taxed lines cannot post."),
        ]),
        ->(code) { Master.tax_code_json(Master.get_tax_code(code)) }, :create_tax_code, :update_tax_code, by_code: true
      ),
      "payment-terms" => collection(
        "Payment terms", "payment term", -> { Master.list_payment_terms },
        [Column.of("Code", "code"), Column.of("Name", "name"), Column.of("Due days", "due_days", numeric: true)],
        ->(_) {
          [Field.of("code", "Code", required: true, readonly_on_edit: true), Field.of("name", "Name", required: true),
           Field.of("due_days", "Due days", "int")]
        },
        ->(code) { Master.payment_term_json(Master.get_payment_term(code)) }, :create_payment_term, :update_payment_term,
        by_code: true
      ),
      "warehouses" => collection(
        "Warehouses", "warehouse", -> { Master.list_warehouses },
        [Column.of("Code", "code"), Column.of("Name", "name"), Column.of("Status", "is_active", kind: "active")],
        with_active([Field.of("code", "Code", required: true), Field.of("name", "Name", required: true)]),
        ->(id) { Master.warehouse_json(Master.get_warehouse(id)) }, :create_warehouse, :update_warehouse,
        keep: ["address_id"]
      ),
    }.freeze

    def index
      list_page(title: spec.title, rows: spec.list.call, columns: spec.columns,
                link: ->(r) { "#{base}/#{ERB::Util.url_encode(r['id'] || r['code'])}" },
                new: ["#{base}/new", "New #{spec.singular}"])
    end

    def new
      crud_form(title: "New #{spec.singular}", fields: spec.fields.call(nil), initial: {}, back: base,
                done: ->(_) { base }) { |b| Master.public_send(spec.create, b) }
    end

    def edit
      key = spec.by_code ? params[:id] : id
      record = spec.get.call(key)
      crud_form(title: "Edit #{spec.singular}", fields: spec.fields.call(record), initial: record, back: base,
                done: ->(_) { base }, editing: true) do |b|
        spec.keep.each { b.data[_1] = record[_1] }
        Master.public_send(spec.update, key, b)
      end
    end

    private

    def spec = COLLECTIONS.fetch(params[:collection])
    def base = "/#{params[:collection]}"
  end
end
