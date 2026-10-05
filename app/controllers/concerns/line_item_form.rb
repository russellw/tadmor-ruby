# The header-and-lines form shared by invoices, bills, credit notes, and
# orders (domain §13.4 D2, §13.6 O2). Lines post as parallel arrays
# (line_description[] and so on), one entry per table row; public/app.js
# adds and removes rows and previews the totals.
module LineItemForm
  extend ActiveSupport::Concern

  LINE_KEYS = %w[product_id description quantity price account tax_code tax_rate].freeze

  private

  def header_fields(kind)
    c = Ui::Choices
    fields = [
      Ui::Field.of(kind.party_id, kind.sales ? "Customer" : "Supplier", "ref", kind.sales ? c.customers : c.suppliers,
                   required: true),
      Ui::Field.of(kind.number_field, "Number", required: true),
      Ui::Field.of(kind.date_field, "Date", "date", required: true),
    ]
    if (second = kind.second_date)
      text = second == "due_date" ? "Due date" : "Expected #{kind.sales ? 'ship' : 'receipt'} date"
      fields << Ui::Field.of(second, text, "date")
    end
    fields + [
      Ui::Field.of("currency_code", "Currency", "select", c.currencies, required: true),
      Ui::Field.of("reference", "Reference"),
      Ui::Field.of("memo", "Memo", "textarea"),
    ]
  end

  # The posted line table as API line objects. Blank rows are dropped.
  def posted_lines(kind)
    lk = kind.lines
    cols = LINE_KEYS.to_h { [_1, Array(params["line_#{_1}"])] }
    cols["description"].each_index.filter_map do |i|
      get = ->(k) { cols[k][i].to_s.strip }
      next if get.("product_id").empty? && get.("description").empty? && get.("price").empty?

      { "product_id" => get.("product_id").match?(/\A\d+\z/) ? get.("product_id").to_i : nil,
        "description" => get.("description"), "quantity" => get.("quantity").presence,
        lk.price => get.("price").presence,
        lk.account => get.("account").match?(/\A\d+\z/) ? get.("account").to_i : nil,
        "tax_code" => get.("tax_code").presence, "tax_rate" => get.("tax_rate").presence }
    end
  end

  # GET shows the form; POST saves through the block and goes to the
  # document, or shows the refusal with what was typed.
  def document_form(kind, title:, initial:, initial_lines:, back:)
    values, lines, error = initial, initial_lines, nil
    if request.post?
      fields = header_fields(kind)
      data = fields.to_h { [_1.name, _1.to_json_value(params[_1.name])] }
      data["lines"] = posted_lines(kind)
      saved, error = attempt { yield Body.new(data) }
      return redirect_to("/#{kind.collection}/#{saved}") if error.nil?

      values = fields.to_h { [_1.name, params[_1.name].to_s] }
      lines = data["lines"]
    end
    lk = kind.lines
    rows = (lines.presence || [{}]).map do |l|
      { "product_id" => l["product_id"], "description" => l["description"].to_s, "quantity" => l["quantity"] || "1",
        "price" => l[lk.price].to_s, "account" => l[lk.account], "tax_code" => l["tax_code"],
        "tax_rate" => l["tax_rate"] || "0" }
    end
    page "ui/document_form", title:, back:, error:, kind:, lines: rows,
                             header: Ui::Form.new(header_fields(kind), values),
                             product_choices: keep(Ui::Choices.products.call, rows, "product_id"),
                             account_choices: keep(Ui::Choices.postable_accounts.call, rows, "account"),
                             tax_choices: keep(Ui::Choices.tax_codes.call, rows, "tax_code"),
                             client_data: client_data(kind)
  end

  # What app.js needs to fill a line from its product and tax code, and a
  # document's currency from its party.
  def client_data(kind)
    products = Product.where(is_active: true).to_h do |p|
      [p.id, { description: p.name, tax_code: p.tax_code, price: kind.sales ? Values.fmt4(p.unit_price) : nil,
               account: kind.sales ? p.revenue_account_id : nil }]
    end
    { products:, taxes: TaxCode.all.to_h { [_1.code, Values.fmt4(_1.rate)] },
      partyCurrency: kind.party_model.where(is_active: true).pluck(:id, :currency_code).to_h }
  end

  # Pickers offer active records, plus any inactive one a line already uses.
  def keep(choices, lines, key)
    have = choices.map { _1[0].to_s }
    extra = lines.filter_map { _1[key]&.to_s.presence }.uniq - have
    choices + extra.sort.map { [_1, "#{_1} (inactive)"] }
  end

  def email_recipients = params[:to].to_s.tr(";", ",").split(",").map(&:strip).reject(&:empty?)
end
