class BankStatementLine < ApplicationRecord
  belongs_to :statement, class_name: "BankStatement"
  belongs_to :journal_line, optional: true
end
