# Stock movements (spec/api.md §5.12, domain §3, §4).
#
# Quantity on hand and value are sums over movements. A movement is posted
# exactly when it carries a journal entry; only receipts and issues post.
module Stock
  TYPES = %w[receipt issue adjustment transfer_in transfer_out].freeze
  POSITIVE = %w[receipt transfer_in].freeze
  NEGATIVE = %w[issue transfer_out].freeze

  module_function

  def json(sm)
    { "id" => sm.id, "product_id" => sm.product_id, "warehouse_id" => sm.warehouse_id,
      "movement_date" => Values.fmt_date(sm.movement_date), "movement_type" => sm.movement_type,
      "status" => sm.journal_entry_id ? "posted" : "draft", "quantity" => Values.fmt4(sm.quantity),
      "unit_cost" => Values.fmt4(sm.unit_cost), "total_cost" => Values.fmt4(sm.total_cost),
      "reference" => sm.reference, "notes" => sm.notes, "journal_entry_id" => sm.journal_entry_id,
      "source_type" => sm.source_type }
  end

  def list = StockMovement.order(movement_date: :desc, id: :desc).map { json(_1) }

  def get(id) = StockMovement.includes(:product, :warehouse).find_by(id:) || raise(ApiError::NotFound, "stock movement not found")

  def required(b)
    b.required_id("product_id")
    b.required_id("warehouse_id")
    b.required_str("movement_type")
    raise ApiError::BadRequest, "quantity is required" if b.str("quantity").blank?
  end

  def fields(b)
    type = b.str("movement_type")
    raise ApiError::Unprocessable, "movement_type must be one of #{TYPES.join(', ')}" unless TYPES.include?(type)

    qty = b.decimal("quantity")
    cost = b.decimal("unit_cost", default: Values::ZERO)
    raise ApiError::Unprocessable, "quantity must not be zero" if qty.zero?
    if (POSITIVE.include?(type) && qty.negative?) || (NEGATIVE.include?(type) && qty.positive?)
      raise ApiError::Unprocessable, "a #{type} must have a #{POSITIVE.include?(type) ? 'positive' : 'negative'} quantity"
    end
    raise ApiError::Unprocessable, "unit_cost must not be negative" if cost.negative?

    Values.check_magnitude(Values.round4(qty * cost), "total cost")
    product = Product.find_by(id: b.int("product_id")) || raise(ApiError::Unprocessable, "unknown product_id")
    unless product.track_inventory && product.is_active
      raise ApiError::Unprocessable, "the product must be active and inventory-tracked"
    end

    { product_id: product.id, warehouse_id: b.int("warehouse_id"), movement_type: type,
      movement_date: b.date("movement_date") || Values.today, quantity: qty, unit_cost: cost,
      reference: b.text("reference"), notes: b.text("notes") }
  end

  def create(b, user = nil)
    required(b)
    StockMovement.create!(fields(b).merge(created_by: user&.id)).id
  end

  def lock(id)
    sm = StockMovement.lock.find_by(id:) || raise(ApiError::NotFound, "stock movement not found")
    raise ApiError::Conflict, "the stock movement is posted" if sm.journal_entry_id

    sm
  end

  def update(id, b)
    required(b)
    sm = lock(id)
    raise ApiError::Conflict, "the stock movement was produced by order fulfilment and cannot be edited" if sm.source_type

    StockMovement.where(id:).update_all(fields(b))
  end

  def delete(id)
    lock(id)
    StockMovement.where(id:).delete_all
  end
end
