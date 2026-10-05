class SupplierPayment < ApplicationRecord
  include PaymentMethodColumn
  belongs_to :supplier
end
