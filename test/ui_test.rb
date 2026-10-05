require "test_helper"

# Walk the server-rendered UI through the checklist of spec/domain.md §13.
#
# These drive the HTML pages through Rails' integration test session: every
# screen renders, forms save through the services, and refusals come back as
# the server's message next to the action. The JSON API itself is covered by
# the conformance suite.
class UiTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email: "admin@example.com", full_name: "Ada Admin",
                          password_hash: Auth.hash_password("admin-pass"), is_admin: true)
    @clerk = User.create!(email: "clerk@example.com", full_name: "Carl Clerk", password_hash: Auth.hash_password("clerk-pass"))
    @acct = Account.pluck(:code, :id).to_h
    @today = Values.today
    FiscalYear.create!(name: "FY#{@today.year}", start_date: @today.beginning_of_year, end_date: @today.end_of_year)
    org = Organization.create!(name: "Acme Ltd", email: "ap@acme.example")
    @customer = Customer.create!(organization_id: org.id, ar_account_id: @acct["1100"], currency_code: "USD")
    sup = Organization.create!(name: "Parts Co")
    @supplier = Supplier.create!(organization_id: sup.id, ap_account_id: @acct["2000"], currency_code: "USD")
    @product = Product.create!(sku: "WID", name: "Widget", unit_price: "12.5", revenue_account_id: @acct["4000"],
                               track_inventory: true, inventory_account_id: @acct["1200"], cogs_account_id: @acct["5000"],
                               tax_code: "STD")
    @warehouse = Warehouse.create!(code: "MAIN", name: "Main")
  end

  def login(user = @admin) = cookies[Auth::COOKIE] = Auth.start_session(user)

  # A form POST, carrying the token every UI form does.
  def submit(url, fields = {})
    token = OpenSSL::HMAC.hexdigest("SHA256", cookies[Auth::COOKIE].to_s, "tadmor form")
    post url, params: fields.merge(form_token: token)
  end

  def page(url, status: 200)
    get url
    assert_equal status, response.status, "GET #{url}"
    response.body
  end

  def invoice(number: "INV-1", qty: "2", price: "10", date: @today, due: nil)
    submit "/sales-invoices/new", "customer_id" => @customer.id, "invoice_number" => number,
                                  "invoice_date" => date.iso8601, "due_date" => due&.iso8601.to_s, "currency_code" => "USD",
                                  "line_product_id" => [@product.id.to_s], "line_description" => ["Widgets"],
                                  "line_quantity" => [qty], "line_price" => [price], "line_account" => [""],
                                  "line_tax_code" => [""], "line_tax_rate" => ["0"]
    assert_equal 302, response.status, response.body[0, 2000]
    SalesInvoice.find_by!(invoice_number: number)
  end

  # -- G: general -------------------------------------------------------------

  test "login is the only page without a session" do # G1, G2
    get "/sales-invoices"
    assert_redirected_to "/login?next=%2Fsales-invoices"
    post "/login", params: { email: "admin@example.com", password: "wrong" }
    assert_includes response.body, "Invalid email or password"
    post "/login", params: { email: " ADMIN@example.com ", password: "admin-pass", next: "/products" }
    assert_redirected_to "/products"
    assert_includes page("/"), "Ada Admin"
    submit "/logout"
    get "/"
    assert_equal 302, response.status
  end

  test "every navigation link works" do # G3
    login
    nav = page("/")[%r{<nav class="sidebar".*?</nav>}m]
    links = nav.scan(/<a href="(\/[^"]*)"/).flatten.uniq
    assert_operator links.size, :>, 25
    links.each { page(_1) }
  end

  test "admin actions are hidden from users" do # G4
    login(@clerk)
    refute_includes page("/"), 'href="/users"'
    page("/users", status: 403)
    assert_includes page("/settings"), "Only administrators can change these"
    inv = invoice
    submit "/sales-invoices/#{inv.id}/post"
    refute_includes page("/sales-invoices/#{inv.id}"), ">Unpost<"
  end

  test "refusals show the server message" do # G5
    login
    submit "/organizations/new", "name" => ""
    assert_includes response.body, "name is required"
    inv = invoice(price: "0")
    submit "/sales-invoices/#{inv.id}/post"
    assert_includes response.body, "total must be greater than zero"
  end

  test "a form from another session is refused" do
    login
    post "/organizations/new", params: { name: "Forged", form_token: "nope" }
    assert_equal 403, response.status
    assert_nil Organization.find_by(name: "Forged")
  end

  test "deletes ask first" do # G6
    login
    inv = invoice
    assert_includes page("/sales-invoices/#{inv.id}/delete"), "cannot be undone"
    assert SalesInvoice.exists?(inv.id)
    submit "/sales-invoices/#{inv.id}/delete"
    refute SalesInvoice.exists?(inv.id)
  end

  test "amounts are exact" do # G7
    login
    inv = invoice(qty: "1.00005", price: "10.0001")
    detail = page("/sales-invoices/#{inv.id}")
    assert_includes detail, "10.0011" # round(1.0001 × 10.0001, 4)
    assert_includes detail, "USD"
  end

  test "an unknown address is not found" do # G8
    login
    assert_includes page("/no-such-page", status: 404), "Not found"
    page("/sales-invoices/999999", status: 404)
  end

  # -- H: home ----------------------------------------------------------------

  test "home shows outstanding and overdue" do # H1–H5
    login
    inv = invoice(date: @today - 40, due: @today - 5)
    submit "/sales-invoices/#{inv.id}/post"
    home = page("/")
    assert_includes home, "USD 20.00"
    assert_includes home, %(href="/sales-invoices/#{inv.id}")
    %w[sales-invoices customer-payments purchase-bills supplier-payments sales-orders purchase-orders].each do |c|
      assert_includes home, %(href="/#{c}/new")
    end
  end

  # -- M: master data -----------------------------------------------------------

  test "master data forms" do # M1–M6
    login
    submit "/organizations/new", "name" => "Globex", "country_code" => "US"
    assert_redirected_to "/organizations"
    org = Organization.find_by!(name: "Globex")
    submit "/customers/new", "organization_id" => org.id, "customer_number" => "C-9", "credit_limit" => "500"
    c = Customer.find_by!(organization_id: org.id)
    # The organization is read-only on edit, and deactivation is through the form.
    submit "/customers/#{c.id}", "organization_id" => 1, "customer_number" => "C-9"
    c.reload
    assert_equal [org.id, false, nil], [c.organization_id, c.is_active, c.credit_limit]
    assert_includes page("/customers"), "Inactive"
    form = page("/accounts/#{@acct['1000']}")
    refute_includes form[/name="parent_id".*?<\/select>/m], %(value="#{@acct['1000']}") # M4
    page("/tax-codes/STD")
    page("/payment-terms/NET30")
    page("/warehouses/#{@warehouse.id}")
  end

  test "users and settings" do # M7, M8
    login
    submit "/users/new", "email" => "new@example.com", "full_name" => "New", "password" => "short"
    assert_includes response.body, "at least 8 characters"
    submit "/users/#{@admin.id}", "email" => "admin@example.com", "full_name" => "Ada"
    assert_includes response.body, "cannot deactivate yourself"
    submit "/users/#{@clerk.id}/password", "password" => "another-pass"
    assert Auth.authenticate("clerk@example.com", "another-pass")
    assert_includes page("/settings"), "FX gain/loss"
  end

  # -- D, P: documents and payments ----------------------------------------------

  test "invoice lifecycle" do # D1–D7
    login
    assert_includes page("/sales-invoices/new"), 'id="client-data"' # prefill data for app.js
    inv = invoice
    assert_includes page("/sales-invoices"), "INV-1"
    detail = page("/sales-invoices/#{inv.id}")
    ["Post", "Edit", "Delete", "/pdf", "Email"].each { assert_includes detail, _1 }
    submit "/sales-invoices/#{inv.id}/post"
    inv.reload
    assert_equal "posted", inv.status
    detail = page("/sales-invoices/#{inv.id}")
    assert_includes detail, "/journal-entries/#{inv.journal_entry_id}"
    assert_includes detail, "Unpost"
    submit "/sales-invoices/#{inv.id}/email", "to" => ""
    assert_includes response.body, "not configured" # D7: 501 when sending is disabled
    get "/api/sales-invoices/#{inv.id}/pdf"
    assert_equal "application/pdf", response.media_type
    assert response.body.start_with?("%PDF-")
    submit "/sales-invoices/#{inv.id}/unpost"
    assert_equal "draft", inv.reload.status
  end

  test "payment and apply" do # P1–P4
    login
    inv = invoice
    submit "/sales-invoices/#{inv.id}/post"
    submit "/customer-payments/new", "customer_id" => @customer.id, "payment_date" => @today.iso8601,
                                     "currency_code" => "USD", "amount" => "15", "method" => "transfer",
                                     "deposit_account_id" => @acct["1000"]
    pay = CustomerPayment.sole
    assert_redirected_to "/customer-payments/#{pay.id}"
    submit "/customer-payments/#{pay.id}/post"
    submit "/customer-payments/#{pay.id}/apply"
    detail = page("/customer-payments/#{pay.id}")
    assert_includes detail, "INV-1"
    assert_includes detail, "15.00"
    assert_includes page("/customer-payments"), "Transfer"
  end

  # -- O: orders --------------------------------------------------------------------

  test "order fulfilment" do # O1–O7
    login
    submit "/sales-orders/new", "customer_id" => @customer.id, "order_number" => "SO-1", "order_date" => @today.iso8601,
                                "currency_code" => "USD", "line_product_id" => [@product.id.to_s],
                                "line_description" => ["Widgets"], "line_quantity" => ["5"], "line_price" => ["12.5"],
                                "line_account" => [""], "line_tax_code" => [""], "line_tax_rate" => ["0"]
    order = SalesOrder.find_by!(order_number: "SO-1")
    assert_redirected_to "/sales-orders/#{order.id}"
    submit "/sales-orders/#{order.id}/confirm"
    line = SalesOrderLine.find_by!(order_id: order.id)
    assert_includes page("/sales-orders/#{order.id}/invoice"), %(name="qty_#{line.id}")
    submit "/sales-orders/#{order.id}/invoice", "number" => "INV-SO-1", "date" => @today.iso8601, "qty_#{line.id}" => "2"
    inv = SalesInvoice.find_by!(invoice_number: "INV-SO-1")
    assert_redirected_to "/sales-invoices/#{inv.id}"
    assert_includes page("/sales-invoices/#{inv.id}"), "cannot be edited"
    submit "/sales-orders/#{order.id}/ship", "warehouse_id" => @warehouse.id, "movement_date" => @today.iso8601,
                                             "qty_#{line.id}" => "5"
    assert_includes response.body, "Stock movement"
    detail = page("/sales-orders/#{order.id}")
    assert_includes detail, "Partial"
    refute_includes detail, "Cancel order" # O4: fulfilled orders cannot be cancelled
  end

  # -- S: inventory -------------------------------------------------------------------

  test "stock movements" do # S1–S3
    login
    submit "/stock-movements/new", "product_id" => @product.id, "warehouse_id" => @warehouse.id,
                                   "movement_type" => "issue", "movement_date" => @today.iso8601, "quantity" => "3",
                                   "unit_cost" => "2"
    sm = StockMovement.sole
    assert_equal BigDecimal("-3"), sm.quantity # S2: signed by the type
    assert_redirected_to "/stock-movements/#{sm.id}"
    submit "/stock-movements/#{sm.id}/post"
    assert sm.reload.journal_entry_id
    assert_includes page("/stock-movements/#{sm.id}"), "Unpost"
    assert_includes page("/inventory-valuation"), "WID"
  end

  # -- R: reports -----------------------------------------------------------------------

  test "reports" do # R1–R8
    login
    inv = invoice
    submit "/sales-invoices/#{inv.id}/post"
    inv.reload
    assert_includes page("/reports/profit-and-loss"), "Net income"
    assert_includes page("/reports/balance-sheet?as_of=#{@today.iso8601}"), "Current earnings"
    assert_includes page("/reports/cash-flow"), "Opening cash"
    assert_includes page("/reports/trial-balance"), "/accounts/#{@acct['1100']}/ledger"
    assert_includes page("/accounts/#{@acct['1100']}/ledger"), "20.00"
    assert_includes page("/journal-entries/#{inv.journal_entry_id}"), "Accounts Receivable"
    assert_includes page("/reports/ar-aging"), "Acme Ltd"
    page("/reports/ap-aging")
    assert_includes page("/reports/profit-and-loss?from=yesterday"), "must be a YYYY-MM-DD"
  end

  # -- A: accounting --------------------------------------------------------------------

  test "periods and year-end" do # A1, A2
    login
    submit "/fiscal-years/new", "name" => "FY1990", "start_date" => "1990-01-01", "end_date" => "1990-12-31"
    assert_redirected_to "/periods"
    y = FiscalYear.find_by!(name: "FY1990")
    submit "/accounting-periods/new", "fiscal_year_id" => y.id, "name" => "1990-01", "start_date" => "1990-01-01",
                                      "end_date" => "1990-01-31"
    assert_includes page("/accounting-periods/new"), 'value="1990-02"' # the month after the latest period
    period = AccountingPeriod.find_by!(name: "1990-01")
    submit "/accounting-periods/#{period.id}/toggle" # closed in one step
    assert_equal "closed", period.reload.status
    submit "/accounting-periods/#{period.id}/toggle"
    assert_equal "open", period.reload.status
    assert_includes page("/fiscal-years/#{y.id}/close"), "Retained Earnings"
    submit "/fiscal-years/#{y.id}/close", "retained_earnings_account_id" => @acct["3000"]
    assert_equal "closed", y.reload.status
    login(@clerk)
    page("/fiscal-years/#{y.id}/close", status: 403)
  end

  test "exchange rates" do # A3
    login
    submit "/exchange-rates/new", "currency_code" => "EUR", "rate_date" => "2026-01-02", "rate" => "1.125"
    assert_includes page("/exchange-rates"), "1.125"
    submit "/exchange-rates/EUR/2026-01-02", "rate" => "1.2"
    assert_includes page("/exchange-rates"), "1.2"
    submit "/exchange-rates/EUR/2026-01-02/delete"
    refute_includes page("/exchange-rates").split("<table").last, "EUR"
  end

  test "bank reconciliation" do # A4, A5
    login
    accounts = page("/bank-statements/new")[/name="account_id".*?<\/select>/m]
    assert_includes accounts, "1000 Cash"
    refute_includes accounts, "1100" # cash accounts only
    pay = CustomerPayment.create!(customer_id: @customer.id, payment_date: @today, currency_code: "USD", amount: "40",
                                  deposit_account_id: @acct["1000"])
    Posting.post_payment(Kinds::CUSTOMER_PAYMENT, pay.id)
    submit "/bank-statements/new", "account_id" => @acct["1000"], "statement_date" => @today.iso8601,
                                   "opening_balance" => "0", "closing_balance" => "40", "reference" => "S1"
    st = BankStatement.sole
    submit "/bank-statements/#{st.id}/import", "csv" => "date,description,amount\nnot-a-date,x,1\n"
    assert_includes response.body, "not a YYYY-MM-DD date"
    submit "/bank-statements/#{st.id}/import", "csv" => "date,description,amount\n#{@today.iso8601},Deposit,40\n"
    assert_includes page("/bank-statements/#{st.id}"), "Match"
    submit "/bank-statements/#{st.id}/lines", "txn_date" => @today.iso8601, "description" => "Stray", "amount" => "5"
    stray = BankStatementLine.find_by!(statement_id: st.id, description: "Stray")
    submit "/bank-statements/#{st.id}/lines/#{stray.id}/delete"
    refute BankStatementLine.exists?(stray.id)
    submit "/bank-statements/#{st.id}/auto-match"
    line = BankStatementLine.find_by!(statement_id: st.id)
    assert line.journal_line_id
    submit "/bank-statements/#{st.id}/lines/#{line.id}/unmatch"
    assert_nil line.reload.journal_line_id
    submit "/bank-statements/#{st.id}/auto-match"
    submit "/bank-statements/#{st.id}/reconcile"
    assert_equal "reconciled", st.reload.status
    assert_includes page("/bank-statements/#{st.id}"), "Reopen"
  end
end
