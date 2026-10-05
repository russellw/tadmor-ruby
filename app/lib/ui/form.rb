module Ui
  # A declarative form: its fields, the values shown, and whether it edits an
  # existing record (some fields are then read-only and sent back unchanged).
  class Form
    attr_reader :fields, :values, :editing

    def initialize(fields, values = {}, editing: false)
      @fields = fields
      @values = values.to_h.stringify_keys
      @editing = editing
    end

    def readonly?(field) = editing && field.readonly_on_edit

    # The posted form as the API's request body.
    def body(post)
      Body.new(fields.to_h do |f|
        [f.name, readonly?(f) ? values[f.name] : f.to_json_value(post[f.name])]
      end)
    end

    # Show what the user typed after a refused submission.
    def redisplay(post)
      fields.each do |f|
        next if readonly?(f)

        values[f.name] = f.type == "bool" ? post[f.name] == "on" : post[f.name].to_s
      end
      self
    end

    Row = Data.define(:field, :value, :choices, :readonly)

    # Fields paired with their current values and choices, for the template.
    def rows
      fields.map do |f|
        value = values[f.name]
        choices = f.choices&.call
        # Keep an inactive current value selectable rather than losing it.
        if choices && value.present? && choices.none? { |v, _| v.to_s == value.to_s }
          choices += [[value, "#{value} (inactive)"]]
        end
        Row.new(f, value.nil? ? "" : value, choices, readonly?(f))
      end
    end
  end
end
