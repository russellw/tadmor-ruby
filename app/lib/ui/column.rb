module Ui
  # A column of a list. `key` is a row hash key or a callable on the row.
  # Kinds: text, amount, qty, bool, active, status, label.
  Column = Data.define(:label, :key, :numeric, :kind) do
    def self.of(label, key, numeric: false, kind: "text") = new(label:, key:, numeric:, kind:)

    def value(row) = key.respond_to?(:call) ? key.call(row) : row[key]
  end
end
