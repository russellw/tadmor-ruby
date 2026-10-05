class PurchaseBill < ApplicationRecord
  belongs_to :supplier
  has_one :bal, class_name: "PurchaseBillBalance", foreign_key: :bill_id
end
