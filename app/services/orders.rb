# Sales and purchase orders: lifecycle and fulfilment (domain §6).
#
# Orders never post. Fulfilment creates draft documents and stock
# movements linked back to the order lines, and the fulfilment views derive
# what has been invoiced, billed, shipped, or received from those links.
module Orders
  module_function

  def order_json(kind, o)
    f = o.fulfilment
    { "id" => o.id, "order_number" => o.order_number, kind.party_id => o[kind.party_id],
      "order_date" => Values.fmt_date(o.order_date), kind.expected_date => Values.fmt_date(o[kind.expected_date]),
      "currency_code" => o.currency_code, "status" => o.status, "total" => Values.fmt4(o.total),
      "#{kind.billed}_status" => f["#{kind.billed}_status"], "#{kind.moved}_status" => f["#{kind.moved}_status"],
      "reference" => o.reference, "memo" => o.memo }
  end

  def scope(kind) = kind.model.includes(:fulfilment, kind.party.to_sym => :organization)

  def list(kind) = scope(kind).order(order_date: :desc, id: :desc).map { order_json(kind, _1) }

  def get(kind, id) = scope(kind).find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")

  def quantity_names(kind)
    ["qty_#{kind.billed}", "qty_#{kind.moved}", "qty_to_#{kind.bill_verb}", "qty_to_#{kind.move_verb}"]
  end

  def lines(kind, id)
    get(kind, id)
    Documents.lines_of(kind, id).includes(:fulfilment).map do |line|
      j = Documents.line_json(kind, line).merge("order_line_id" => line.id)
      quantity_names(kind).each { |name| j[name] = Values.fmt4(line.fulfilment[name]) }
      j
    end
  end

  # -- Lifecycle -------------------------------------------------------------------

  def lock(kind, id) = kind.model.lock.find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")

  def confirm(kind, id)
    o = lock(kind, id)
    raise ApiError::Conflict, "the #{kind.noun} is #{o.status}, not draft" if o.status != "draft"
    raise ApiError::Unprocessable, "the #{kind.noun} has no lines" unless Documents.lines_of(kind, id).exists?

    kind.model.where(id:).update_all(status: "open")
  end

  def close(kind, id)
    o = lock(kind, id)
    raise ApiError::Conflict, "the #{kind.noun} is #{o.status}, not open" if o.status != "open"

    kind.model.where(id:).update_all(status: "closed")
  end

  def fulfilled?(kind, id)
    kind.line_fulfilment.where(order_line_id: kind.lines.model.where(order_id: id).select(:id))
        .where("qty_#{kind.billed} > 0 OR qty_#{kind.moved} > 0").exists?
  end

  def cancel(kind, id)
    o = lock(kind, id)
    raise ApiError::Conflict, "the #{kind.noun} is #{o.status}" unless %w[draft open].include?(o.status)
    if o.status == "open" && fulfilled?(kind, id)
      raise ApiError::Conflict, "the #{kind.noun} has been partly fulfilled and cannot be cancelled"
    end

    kind.model.where(id:).update_all(status: "cancelled")
  end

  # -- Fulfilment ------------------------------------------------------------------

  # {order_line_id => quantity} from a fulfilment body; empty means everything.
  def requested(b)
    b.list("lines").each.with_index(1).to_h do |line, i|
      line_id = line.int("order_line_id")
      raise ApiError::BadRequest, "line #{i}: order_line_id is required" if line_id.nil?

      [line_id, line.decimal("quantity", default: Values::ZERO)]
    end
  end

  def quantity(remaining, requested, line_id)
    requested.empty? ? remaining : [remaining, requested.fetch(line_id, Values::ZERO)].min
  end

  def open_order(kind, id)
    o = lock(kind, id)
    raise ApiError::Conflict, "the #{kind.noun} is #{o.status}, not open" if o.status != "open"

    o
  end

  # Invoice a sales order or bill a purchase order (domain §6.3).
  def invoice(kind, id, b, user = nil)
    doc = kind.document
    number = b.required_str(doc.number)
    b.required_str(doc.date)
    o = open_order(kind, id)
    date = b.date(doc.date)
    due = b.date("due_date")
    raise ApiError::Unprocessable, "due_date must not be before #{doc.date}" if due && due < date

    wanted = requested(b)
    lk = kind.lines
    picked = Documents.lines_of(kind, id).includes(:fulfilment).reorder(:id).filter_map do |line|
      qty = quantity(line.fulfilment["qty_to_#{kind.bill_verb}"], wanted, line.id)
      [line, qty] if qty.positive?
    end
    raise ApiError::Unprocessable, "nothing is left to #{kind.bill_verb} on this #{kind.noun}" if picked.empty?

    header = { doc.number => number, doc.party_id => o[kind.party_id], doc.date => date, "due_date" => due,
               "currency_code" => o.currency_code, "reference" => o.order_number }
    Documents.check_number_free(doc, header)
    created = doc.model.create!(header.merge("created_by" => user&.id))
    doc.lines.model.insert_all!(picked.each.with_index(1).map do |(line, qty), n|
      { doc.lines.parent_id => created.id, "line_no" => n, "product_id" => line.product_id,
        "description" => line.description, "quantity" => qty, "tax_code" => line.tax_code,
        "tax_rate" => line.tax_rate, "order_line_id" => line.id, lk.price => line[lk.price],
        lk.account => line[lk.account] }
    end)
    created.id
  end

  # The moving-average unit cost of a product in a warehouse (domain §6.3).
  def avg_cost(product_id, warehouse_id)
    ActiveRecord::Base.connection.select_value(
      ActiveRecord::Base.sanitize_sql(["SELECT avg_unit_cost FROM stock_on_hand WHERE product_id = ? AND warehouse_id = ?",
                                       product_id, warehouse_id]),
    ) || Values::ZERO
  end

  # Ship a sales order or receive a purchase order into draft movements.
  def move(kind, id, b, user = nil)
    warehouse = b.required_id("warehouse_id")
    o = open_order(kind, id)
    date = b.date("movement_date") || Values.today
    wanted = requested(b)
    rate = kind.sales ? nil : Posting.rate_for(o.currency_code, date)
    lines = Documents.lines_of(kind, id).includes(:fulfilment).reorder(:id).to_a
    tracked = Product.where(id: lines.filter_map(&:product_id), track_inventory: true, is_active: true).pluck(:id).to_set
    created = lines.filter_map do |line|
      next unless tracked.include?(line.product_id)

      qty = quantity(line.fulfilment["qty_to_#{kind.move_verb}"], wanted, line.id)
      next unless qty.positive?

      fields = if kind.sales
        { unit_cost: avg_cost(line.product_id, warehouse), quantity: -qty, movement_type: "issue",
          source_type: "sales_order_line" }
      else
        { unit_cost: Values.round4(line.unit_cost * rate), quantity: qty, movement_type: "receipt",
          source_type: "purchase_order_line" }
      end
      StockMovement.create!(fields.merge(product_id: line.product_id, warehouse_id: warehouse, movement_date: date,
                                         source_id: line.id, reference: b.text("reference"), created_by: user&.id)).id
    end
    raise ApiError::Unprocessable, "nothing is left to #{kind.move_verb} on this #{kind.noun}" if created.empty?

    created
  end
end
