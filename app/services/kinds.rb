# Descriptors for the document kinds that share code paths.
#
# Invoices, bills, and both kinds of credit note share one lifecycle and one
# line shape; sales and purchase orders share that line shape too; customer
# and supplier payments mirror each other. Each kind records the names that
# differ, so the services are written once (spec/api.md §5.9–5.10).
module Kinds
  LineKind = Data.define(:model, :parent, :price, :account, :order_linked) do
    def parent_id = "#{parent}_id"
  end

  def self.sales_line(model, parent, order_linked: false)
    LineKind.new(model:, parent:, price: "unit_price", account: "revenue_account_id", order_linked:)
  end

  def self.purchase_line(model, parent, order_linked: false)
    LineKind.new(model:, parent:, price: "unit_cost", account: "expense_account_id", order_linked:)
  end

  module Party
    def party = sales ? "customer" : "supplier"
    def party_id = "#{party}_id"
    def party_model = sales ? Customer : Supplier
    def control_account = sales ? "ar_account_id" : "ap_account_id"
  end

  # Invoices, bills, and credit notes.
  DocKind = Data.define(:collection, :label, :noun, :model, :balance, :lines, :sales, :credit, :number, :date,
                        :due_date, :status_field, :pdf_prefix, :number_per_party, :applications) do
    include Party

    def number_field = number
    def date_field = date
    def second_date = due_date ? "due_date" : nil
    def order? = false

    # Whether posting debits the party's control account.
    def control_debit = sales != credit
  end

  SALES_INVOICE = DocKind.new(
    collection: "sales-invoices", label: "Invoice", noun: "invoice", model: SalesInvoice,
    balance: SalesInvoiceBalance, lines: sales_line(SalesInvoiceLine, "invoice", order_linked: true),
    sales: true, credit: false, number: "invoice_number", date: "invoice_date", due_date: true,
    status_field: "payment_status", pdf_prefix: "invoice", number_per_party: false, applications: nil,
  )
  PURCHASE_BILL = DocKind.new(
    collection: "purchase-bills", label: "Bill", noun: "bill", model: PurchaseBill,
    balance: PurchaseBillBalance, lines: purchase_line(PurchaseBillLine, "bill", order_linked: true),
    sales: false, credit: false, number: "bill_number", date: "bill_date", due_date: true,
    status_field: "payment_status", pdf_prefix: "bill", number_per_party: true, applications: nil,
  )
  SALES_CREDIT_NOTE = DocKind.new(
    collection: "sales-credit-notes", label: "Credit Note", noun: "credit note", model: SalesCreditNote,
    balance: SalesCreditNoteBalance, lines: sales_line(SalesCreditNoteLine, "credit_note"),
    sales: true, credit: true, number: "credit_note_number", date: "credit_note_date", due_date: false,
    status_field: "application_status", pdf_prefix: "credit-note", number_per_party: false,
    applications: SalesCreditApplication,
  )
  PURCHASE_CREDIT_NOTE = DocKind.new(
    collection: "purchase-credit-notes", label: "Credit Note", noun: "supplier credit", model: PurchaseCreditNote,
    balance: PurchaseCreditNoteBalance, lines: purchase_line(PurchaseCreditNoteLine, "credit_note"),
    sales: false, credit: true, number: "credit_note_number", date: "credit_note_date", due_date: false,
    status_field: "application_status", pdf_prefix: "supplier-credit", number_per_party: true,
    applications: PurchaseCreditApplication,
  )
  DOCUMENTS = [SALES_INVOICE, PURCHASE_BILL, SALES_CREDIT_NOTE, PURCHASE_CREDIT_NOTE].index_by(&:collection).freeze

  OrderKind = Data.define(:collection, :label, :noun, :model, :fulfilment, :line_fulfilment, :lines, :sales,
                          :expected_date, :billed, :moved, :bill_verb, :move_verb, :pdf_prefix, :document) do
    include Party

    def number_field = "order_number"
    def date_field = "order_date"
    def second_date = expected_date
    def order? = true
  end

  SALES_ORDER = OrderKind.new(
    collection: "sales-orders", label: "Sales Order", noun: "sales order", model: SalesOrder,
    fulfilment: SalesOrderFulfilment, line_fulfilment: SalesOrderLineFulfilment,
    lines: sales_line(SalesOrderLine, "order"), sales: true, expected_date: "expected_ship_date",
    billed: "invoiced", moved: "shipped", bill_verb: "invoice", move_verb: "ship", pdf_prefix: "sales-order",
    document: SALES_INVOICE,
  )
  PURCHASE_ORDER = OrderKind.new(
    collection: "purchase-orders", label: "Purchase Order", noun: "purchase order", model: PurchaseOrder,
    fulfilment: PurchaseOrderFulfilment, line_fulfilment: PurchaseOrderLineFulfilment,
    lines: purchase_line(PurchaseOrderLine, "order"), sales: false, expected_date: "expected_receipt_date",
    billed: "billed", moved: "received", bill_verb: "bill", move_verb: "receive", pdf_prefix: "purchase-order",
    document: PURCHASE_BILL,
  )
  ORDERS = [SALES_ORDER, PURCHASE_ORDER].index_by(&:collection).freeze

  PaymentKind = Data.define(:collection, :noun, :model, :applications, :sales, :cash_account, :documents) do
    include Party
  end

  CUSTOMER_PAYMENT = PaymentKind.new(
    collection: "customer-payments", noun: "customer payment", model: CustomerPayment,
    applications: PaymentApplication, sales: true, cash_account: "deposit_account_id", documents: SALES_INVOICE,
  )
  SUPPLIER_PAYMENT = PaymentKind.new(
    collection: "supplier-payments", noun: "supplier payment", model: SupplierPayment,
    applications: BillApplication, sales: false, cash_account: "payment_account_id", documents: PURCHASE_BILL,
  )
  PAYMENTS = [CUSTOMER_PAYMENT, SUPPLIER_PAYMENT].index_by(&:collection).freeze

  PAYMENT_METHODS = %w[cash check card transfer other].freeze

  # The payment and credit-note kinds that settle a side's documents.
  def self.settlers(sales) = sales ? [CUSTOMER_PAYMENT, SALES_CREDIT_NOTE] : [SUPPLIER_PAYMENT, PURCHASE_CREDIT_NOTE]

  def self.printable = DOCUMENTS.merge(ORDERS)
end
