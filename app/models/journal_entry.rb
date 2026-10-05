class JournalEntry < ApplicationRecord
  has_many :lines, -> { order(:line_no) }, class_name: "JournalLine"
end
