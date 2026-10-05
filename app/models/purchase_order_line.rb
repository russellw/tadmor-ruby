class PurchaseOrderLine < ApplicationRecord
  has_one :fulfilment, class_name: "PurchaseOrderLineFulfilment", foreign_key: :order_line_id
end
