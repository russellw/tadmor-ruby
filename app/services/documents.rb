# Draft documents: create, replace, delete, and read (spec/api.md §5.9–5.10).
#
# Invoices, bills, credit notes, and orders share the header-and-lines
# shape; payments are header only. Line money and header totals are
# computed by the database (generated columns and triggers), so this module
# writes only the inputs. A PUT replaces the header and the whole line set.
module Documents
  module_function

  # -- Request bodies ------------------------------------------------------------

  # The 400 checks of a header-and-lines body (spec/api.md §5.9).
  def check_required(kind, b)
    b.required_str(kind.number_field)
    b.required_id(kind.party_id)
    b.required_str(kind.date_field)
    b.required_str("currency_code")
    b.list("lines").each.with_index(1) do |line, i|
      raise ApiError::BadRequest, "line #{i}: description is required" if line.str("description").blank?
    end
  end

  def header(kind, b)
    fields = { kind.number_field => b.str(kind.number_field), kind.party_id => b.int(kind.party_id),
               kind.date_field => b.date(kind.date_field), "currency_code" => b.str("currency_code").strip.upcase,
               "reference" => b.text("reference"), "memo" => b.text("memo") }
    if (second = kind.second_date)
      fields[second] = b.date(second)
      if fields[second] && fields[second] < fields[kind.date_field]
        raise ApiError::Unprocessable, "#{second} must not be before #{kind.date_field}"
      end
    end
    fields
  end

  # Parse the line set, checking what the database would refuse.
  def lines(kind, b)
    lk = kind.lines
    b.list("lines").each.with_index(1).map do |line, i|
      qty = line.decimal("quantity", default: BigDecimal(1))
      price = line.decimal(lk.price, default: Values::ZERO)
      rate = line.decimal("tax_rate", Values::RATE, default: Values::ZERO)
      if qty.zero? || (kind.order? && qty.negative?)
        raise ApiError::Unprocessable, "line #{i}: quantity must be #{kind.order? ? 'greater than' : 'other than'} zero"
      end
      raise ApiError::Unprocessable, "line #{i}: tax_rate must not be negative" if rate.negative?

      subtotal = Values.check_magnitude(Values.round4(qty * price), "line #{i} subtotal")
      Values.check_magnitude(subtotal + Values.round4(qty * price * rate * Values::PERCENT), "line #{i} total")
      { "line_no" => i, "product_id" => line.int("product_id"), "description" => line.str("description"),
        "quantity" => qty, lk.price => price, lk.account => line.int(lk.account),
        "tax_code" => line.text("tax_code"), "tax_rate" => rate }
    end
  end

  def insert_lines(kind, doc_id, rows)
    lk = kind.lines
    lk.model.insert_all!(rows.map { _1.merge(lk.parent_id => doc_id) }) if rows.any?
  end

  def check_number_free(kind, fields, id = nil)
    number = kind.number_field
    rows = kind.model.where(number => fields[number])
    rows = rows.where(kind.party_id => fields[kind.party_id]) if !kind.order? && kind.number_per_party
    raise ApiError::Conflict, "#{number} #{fields[number].inspect} is already used" if rows.where.not(id:).exists?
  end

  def create(kind, b, user = nil)
    check_required(kind, b)
    fields = header(kind, b)
    rows = lines(kind, b)
    check_number_free(kind, fields)
    doc = kind.model.create!(fields.merge("created_by" => user&.id))
    insert_lines(kind, doc.id, rows)
    doc.id
  end

  def lock_draft(kind, id)
    doc = kind.model.lock.find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")
    raise ApiError::Conflict, "#{kind.noun} is #{doc.status}, not draft" if doc.status != "draft"

    doc
  end

  def order_linked?(kind, id)
    lk = kind.lines
    lk.order_linked && lk.model.where(lk.parent_id => id).where.not(order_line_id: nil).exists?
  end

  def update(kind, id, b)
    check_required(kind, b)
    lock_draft(kind, id)
    raise ApiError::Conflict, "this #{kind.noun} was produced from an order and cannot be edited" if order_linked?(kind, id)

    fields = header(kind, b)
    rows = lines(kind, b)
    check_number_free(kind, fields, id)
    kind.model.where(id:).update_all(fields)
    kind.lines.model.where(kind.lines.parent_id => id).delete_all
    insert_lines(kind, id, rows)
  end

  def delete(kind, id)
    lock_draft(kind, id)
    kind.lines.model.where(kind.lines.parent_id => id).delete_all
    kind.model.where(id:).delete_all
  end

  # -- Reads: invoices, bills, credit notes -------------------------------------

  def document_json(kind, doc)
    bal = doc.bal
    out = { "id" => doc.id, kind.number => doc[kind.number], kind.party_id => doc[kind.party_id],
            kind.date => Values.fmt_date(doc[kind.date]) }
    out["due_date"] = Values.fmt_date(doc.due_date) if kind.due_date
    out[kind.status_field] = bal[kind.status_field]
    out.merge("currency_code" => doc.currency_code, "status" => doc.status, "total" => Values.fmt4(doc.total),
              "amount_applied" => Values.fmt4(bal.amount_applied), "balance" => Values.fmt4(bal.balance),
              "journal_entry_id" => doc.journal_entry_id, "reference" => doc.reference, "memo" => doc.memo)
  end

  def scope(kind) = kind.model.includes(:bal, kind.party.to_sym => :organization)

  def list_documents(kind)
    scope(kind).order(kind.date => :desc, id: :desc).map { document_json(kind, _1) }
  end

  def get_document(kind, id) = scope(kind).find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")

  def line_json(kind, line)
    lk = kind.lines
    out = { "line_no" => line.line_no, "product_id" => line.product_id, "description" => line.description,
            "quantity" => Values.fmt4(line.quantity), lk.price => Values.fmt4(line[lk.price]),
            "tax_code" => line.tax_code, "tax_rate" => Values.fmt4(line.tax_rate),
            "line_subtotal" => Values.fmt4(line.line_subtotal), "tax_amount" => Values.fmt4(line.tax_amount),
            "line_total" => Values.fmt4(line.line_total), lk.account => line[lk.account] }
    out["order_line_id"] = lk.order_linked ? line.order_line_id : nil unless kind.order?
    out
  end

  def lines_of(kind, id) = kind.lines.model.where(kind.lines.parent_id => id).order(:line_no)

  def list_lines(kind, id)
    get_document(kind, id) unless kind.order?
    lines_of(kind, id).map { line_json(kind, _1) }
  end

  # Applications in creation order: the documents a settler is applied to.
  def applications_json(model, settler_column, settler_id, target)
    model.where(settler_column => settler_id).order(:id).map do |a|
      doc_id = a[target.sales ? "invoice_id" : "bill_id"]
      { "document_id" => doc_id, "document_number" => target.model.where(id: doc_id).pick(target.number),
        "amount_applied" => Values.fmt4(a.amount_applied) }
    end
  end

  def credit_note_applications(kind, id)
    get_document(kind, id)
    applications_json(kind.applications, "credit_note_id", id, kind.sales ? Kinds::SALES_INVOICE : Kinds::PURCHASE_BILL)
  end

  # What has been applied to an invoice or bill, by payments and credit notes.
  def applications_to(kind, id)
    pay, note = Kinds.settlers(kind.sales)
    doc_column = kind.sales ? "invoice_id" : "bill_id"
    payments = pay.applications.where(doc_column => id).order(:id).map do |a|
      p = pay.model.find(a.payment_id)
      { "collection" => pay.collection, "id" => p.id, "label" => "Payment #{p.id}", "date" => p.payment_date,
        "status" => p.status, "amount_applied" => Values.fmt4(a.amount_applied) }
    end
    credits = note.applications.where(doc_column => id).order(:id).map do |a|
      n = note.model.find(a.credit_note_id)
      { "collection" => note.collection, "id" => n.id, "label" => "Credit note #{n.credit_note_number}",
        "date" => n.credit_note_date, "status" => n.status, "amount_applied" => Values.fmt4(a.amount_applied) }
    end
    payments + credits
  end

  # -- Payments ------------------------------------------------------------------

  def payment_required(kind, b)
    b.required_id(kind.party_id)
    b.required_str("payment_date")
    b.required_str("currency_code")
    raise ApiError::BadRequest, "amount is required" if b.str("amount").blank?
  end

  def payment_fields(kind, b)
    amount = b.decimal("amount")
    raise ApiError::Unprocessable, "amount must be greater than 0" unless amount.positive?

    method = b.text("method")
    if method && !Kinds::PAYMENT_METHODS.include?(method)
      raise ApiError::Unprocessable, "method must be one of #{Kinds::PAYMENT_METHODS.join(', ')}"
    end
    { kind.party_id => b.int(kind.party_id), "payment_date" => b.date("payment_date"),
      "currency_code" => b.str("currency_code").strip.upcase, "amount" => amount, "method" => method,
      "reference" => b.text("reference"), kind.cash_account => b.int(kind.cash_account) }
  end

  def create_payment(kind, b, user = nil)
    payment_required(kind, b)
    kind.model.create!(payment_fields(kind, b).merge("created_by" => user&.id)).id
  end

  def update_payment(kind, id, b)
    payment_required(kind, b)
    lock_draft(kind, id)
    kind.model.where(id:).update_all(payment_fields(kind, b))
  end

  def delete_payment(kind, id)
    lock_draft(kind, id)
    kind.model.where(id:).delete_all
  end

  def payment_scope(kind)
    applied = kind.applications.where("#{kind.applications.table_name}.payment_id = #{kind.model.table_name}.id")
                  .select("COALESCE(sum(amount_applied), 0)")
    kind.model.includes(kind.party.to_sym => :organization).select("#{kind.model.table_name}.*", "(#{applied.to_sql}) AS applied")
  end

  def payment_json(kind, p)
    { "id" => p.id, kind.party_id => p[kind.party_id], "payment_date" => Values.fmt_date(p.payment_date),
      kind.cash_account => p[kind.cash_account], "currency_code" => p.currency_code,
      "amount" => Values.fmt4(p.amount), "method" => p.method, "reference" => p.reference, "status" => p.status,
      "amount_applied" => Values.fmt4(p.applied), "unapplied" => Values.fmt4(p.amount - p.applied),
      "journal_entry_id" => p.journal_entry_id }
  end

  def list_payments(kind)
    payment_scope(kind).order(payment_date: :desc, id: :desc).map { payment_json(kind, _1) }
  end

  def get_payment(kind, id) = payment_scope(kind).find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")

  def payment_applications(kind, id)
    get_payment(kind, id)
    applications_json(kind.applications, "payment_id", id, kind.documents)
  end
end
