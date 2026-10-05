class PurchaseCreditNote < ApplicationRecord
  belongs_to :supplier
  has_one :bal, class_name: "PurchaseCreditNoteBalance", foreign_key: :credit_note_id
end
