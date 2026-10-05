class CustomerPayment < ApplicationRecord
  include PaymentMethodColumn
  belongs_to :customer
end
