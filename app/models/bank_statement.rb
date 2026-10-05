class BankStatement < ApplicationRecord
  belongs_to :account
  has_many :lines, class_name: "BankStatementLine", foreign_key: :statement_id
end
