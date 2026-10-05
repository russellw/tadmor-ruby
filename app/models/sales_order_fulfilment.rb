# A row of the sales_order_fulfilment view: the header's fulfilment statuses.
class SalesOrderFulfilment < ApplicationRecord
  self.table_name = "sales_order_fulfilment"
  self.primary_key = "order_id"
end
