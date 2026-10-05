class SalesOrderLine < ApplicationRecord
  has_one :fulfilment, class_name: "SalesOrderLineFulfilment", foreign_key: :order_line_id
end
