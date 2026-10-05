class SalesOrder < ApplicationRecord
  belongs_to :customer
  has_one :fulfilment, class_name: "SalesOrderFulfilment", foreign_key: :order_id
end
