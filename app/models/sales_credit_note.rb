class SalesCreditNote < ApplicationRecord
  belongs_to :customer
  has_one :bal, class_name: "SalesCreditNoteBalance", foreign_key: :credit_note_id
end
