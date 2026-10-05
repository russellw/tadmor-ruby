# A row of the sales_invoice_balances view.
class SalesInvoiceBalance < ApplicationRecord
  self.primary_key = "invoice_id"
end
