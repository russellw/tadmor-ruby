# A row of the purchase_order_fulfilment view: the header's fulfilment statuses.
class PurchaseOrderFulfilment < ApplicationRecord
  self.table_name = "purchase_order_fulfilment"
  self.primary_key = "order_id"
end
