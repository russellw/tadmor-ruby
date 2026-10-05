# A row of the sales_order_line_fulfilment view: what is fulfilled and remains per line.
class SalesOrderLineFulfilment < ApplicationRecord
  self.table_name = "sales_order_line_fulfilment"
  self.primary_key = "order_line_id"
end
