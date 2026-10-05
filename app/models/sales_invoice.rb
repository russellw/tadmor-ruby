class SalesInvoice < ApplicationRecord
  belongs_to :customer
  has_one :bal, class_name: "SalesInvoiceBalance", foreign_key: :invoice_id
end
