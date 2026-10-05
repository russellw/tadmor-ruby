# A row of the purchase_order_line_fulfilment view: what is fulfilled and remains per line.
class PurchaseOrderLineFulfilment < ApplicationRecord
  self.table_name = "purchase_order_line_fulfilment"
  self.primary_key = "order_line_id"
end
