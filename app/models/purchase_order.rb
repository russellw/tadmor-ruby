class PurchaseOrder < ApplicationRecord
  belongs_to :supplier
  has_one :fulfilment, class_name: "PurchaseOrderFulfilment", foreign_key: :order_id
end
