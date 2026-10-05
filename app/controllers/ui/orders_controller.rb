module Ui
  # Sales and purchase orders (domain §13.6, O1–O7).
  class OrdersController < BaseController
    include LineItemForm

    def index
      names = kind.party_model.joins(:organization).pluck(:id, "organizations.name").to_h
      rows = Orders.list(kind).each { _1["party_name"] = names[_1[kind.party_id]] }
      list_page(
        title: kind.sales ? "Sales orders" : "Purchase orders", rows:,
        columns: [Column.of("Number", "order_number"), Column.of(kind.sales ? "Customer" : "Supplier", "party_name"),
                  Column.of("Date", "order_date"), Column.of("Currency", "currency_code"),
                  Column.of("Total", "total", numeric: true, kind: "amount"), Column.of("Status", "status", kind: "status"),
                  Column.of(kind.billed.capitalize, "#{kind.billed}_status", kind: "status"),
                  Column.of(kind.moved.capitalize, "#{kind.moved}_status", kind: "status")],
        link: ->(r) { "/#{c}/#{r['id']}" }, new: ["/#{c}/new", "New #{kind.noun}"],
      )
    end

    def new
      initial = { "order_date" => Values.today.iso8601, "currency_code" => Posting.base_currency }
      document_form(kind, title: "New #{kind.noun}", initial:, initial_lines: [], back: "/#{c}") do |b|
        Documents.create(kind, b, current_user)
      end
    end

    def edit
      order_id = id
      o = Orders.order_json(kind, Orders.get(kind, order_id))
      document_form(kind, title: "Edit #{kind.noun} #{o['order_number']}", initial: o,
                          initial_lines: Orders.lines(kind, order_id), back: detail_path) do |b|
        Documents.update(kind, order_id, b)
        order_id
      end
    end

    def show = detail

    def destroy
      o = Orders.order_json(kind, Orders.get(kind, id))
      error = nil
      if request.post?
        _, error = attempt { Documents.delete(kind, id) }
        return redirect_to("/#{c}") if error.nil?
      end
      page "ui/confirm", title: "Delete #{kind.noun} #{o['order_number']}?", error:, back: detail_path,
                         question: "This deletes draft #{kind.noun} #{o['order_number']} and its lines. It cannot be undone."
    end

    def transition
      name = params[:transition]
      act(name.to_sym) { Orders.public_send(name, kind, id) }
    end

    # O5: invoice (or bill) the order, partially if quantities are lowered.
    def bill
      order_id = id
      o = Orders.order_json(kind, Orders.get(kind, order_id))
      doc = kind.document
      lines = outstanding(order_id, "qty_to_#{kind.bill_verb}")
      values = { "number" => "", "date" => Values.today.iso8601, "due_date" => "" }
      error = nil
      if request.post?
        values = values.keys.to_h { [_1, params[_1].to_s] }
        body = Body.new(doc.number => values["number"].presence, doc.date => values["date"].presence,
                        "due_date" => values["due_date"].presence, "lines" => chosen_lines(lines))
        created, error = attempt { Orders.invoice(kind, order_id, body, current_user) }
        return redirect_to("/#{doc.collection}/#{created}") if error.nil?
      end
      page "ui/order_fulfil", title: "#{kind.bill_verb.capitalize} #{kind.noun} #{o['order_number']}", error:,
                              back: detail_path, billing: true, values:, kind:, rows: rows(lines),
                              number_label: kind.sales ? "Invoice number" : "Bill number",
                              date_label: kind.sales ? "Invoice date" : "Bill date"
    end

    # O6: ship (or receive) the order's stocked lines into draft movements.
    def move
      order_id = id
      o = Orders.order_json(kind, Orders.get(kind, order_id))
      lines = outstanding(order_id, "qty_to_#{kind.move_verb}")
      values = { "warehouse_id" => "", "movement_date" => Values.today.iso8601, "reference" => o["order_number"] }
      error = nil
      if request.post?
        values = values.keys.to_h { [_1, params[_1].to_s] }
        wh = values["warehouse_id"]
        body = Body.new("warehouse_id" => wh.match?(/\A\d+\z/) ? wh.to_i : nil,
                        "movement_date" => values["movement_date"].presence, "reference" => values["reference"].presence,
                        "lines" => chosen_lines(lines))
        created, error = attempt { Orders.move(kind, order_id, body, current_user) }
        if error.nil?
          return page("ui/order_moved", title: "#{kind.moved.capitalize} #{kind.noun} #{o['order_number']}",
                                        movements: created, back: detail_path)
        end
      end
      page "ui/order_fulfil", title: "#{kind.move_verb.capitalize} #{kind.noun} #{o['order_number']}", error:,
                              back: detail_path, billing: false, values:, kind:, rows: rows(lines),
                              warehouses: Choices.warehouses.call
    end

    def email
      return redirect_to(detail_path) unless request.post?

      sent, error = attempt { Printing.email(c, id, email_recipients) }
      error ? detail(email: error) : detail({}, sent)
    end

    private

    def c = params[:collection]
    def kind = Kinds::ORDERS.fetch(c)
    def detail_path = "/#{c}/#{id}"

    # The lines with something left on an axis, each with its remaining quantity.
    def outstanding(order_id, remaining)
      Orders.lines(kind, order_id).select { BigDecimal(_1[remaining]).positive? }.each { _1["remaining"] = _1[remaining] }
    end

    # What the form asks for on each line: the posted quantity, or all that remains.
    def rows(lines)
      lines.each do |l|
        l["chosen"] = request.post? ? params["qty_#{l['order_line_id']}"].to_s.strip : Printing.qty(l["remaining"])
      end
    end

    def chosen_lines(lines)
      lines.map { { "order_line_id" => _1["order_line_id"], "quantity" => params["qty_#{_1['order_line_id']}"].to_s.strip.presence || "0" } }
    end

    def detail(errors = {}, email_result = nil)
      o = Orders.get(kind, id)
      lines = Orders.lines(kind, id)
      line_ids = kind.lines.model.where(order_id: id).select(:id)
      doc = kind.document
      documents = doc.model.where(id: doc.lines.model.where(order_line_id: line_ids).select(doc.lines.parent_id)).order(:id)
      movements = StockMovement.where(source_type: kind.sales ? "sales_order_line" : "purchase_order_line",
                                      source_id: line_ids).order(:id)
      page "ui/order_detail", title: "#{kind.label} #{o.order_number}", kind:, c:, o: Orders.order_json(kind, o), lines:,
                              party: o.public_send(kind.party).organization.name, subtotal: o.subtotal, tax_total: o.tax_total,
                              fulfilled: Orders.fulfilled?(kind, id),
                              can_bill: lines.any? { BigDecimal(_1["qty_to_#{kind.bill_verb}"]).positive? },
                              can_move: lines.any? { BigDecimal(_1["qty_to_#{kind.move_verb}"]).positive? },
                              documents:, movements:, errors:, email_result:
    end
  end
end
