module Ui
  # One field of a declarative form. Types: text, email, password, textarea,
  # decimal, int, date, bool, select, ref (a picker over records).
  # `choices` is a callable returning [[value, label], ...].
  Field = Data.define(:name, :label, :type, :choices, :required, :help, :readonly_on_edit) do
    def self.of(name, label, type = "text", choices = nil, required: false, help: nil, readonly_on_edit: false)
      new(name:, label:, type:, choices:, required:, help:, readonly_on_edit:)
    end

    # An HTML form value in the API body's JSON shape.
    def to_json_value(raw)
      return raw == "on" if type == "bool"
      return nil if raw.nil?

      raw = raw.strip unless type == "password"
      return nil if raw.empty?
      return raw unless %w[int ref].include?(type)

      raw.match?(/\A-?\d+\z/) ? raw.to_i : raw # Body refuses a non-integer with a clear message
    end
  end
end
