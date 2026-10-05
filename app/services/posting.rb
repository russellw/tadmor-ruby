# Posting to the general ledger, and reversing it (domain §4, §7).
#
# Each posting runs in the request's transaction and creates one posted
# journal entry in the document's currency, at the entry's exchange rate,
# with every line carrying both its transaction and its base amounts. The
# schema checks that a posted entry balances in both and touches only
# postable, active accounts in an open period; the checks here come first so
# that each refusal has the status and message the spec gives it (domain §4.2).
module Posting
  ZERO = Values::ZERO

  # A journal line before it is written: amounts in the entry's currency and in base.
  Line = Data.define(:account_id, :debit, :credit, :base_debit, :base_credit, :memo)

  module_function

  def base_currency = GlSetting.current.base_currency

  # The exchange rate a posting in a currency on a date uses (domain §7.1).
  def rate_for(currency, date)
    return BigDecimal(1) if currency == base_currency

    rate = ExchangeRate.where(currency_code: currency, rate_date: ..date).order(rate_date: :desc).pick(:rate)
    raise ApiError::Unprocessable, "no #{currency} exchange rate on or before #{date}" if rate.nil?

    rate
  end

  # Write a posted journal entry.
  def new_entry(date, currency, lines, memo: nil, reference: nil, rate: nil, reverses: nil, closing: false, period: nil)
    period ||= Calendar.period_for_posting(date)
    rate ||= rate_for(currency, date)
    entry = JournalEntry.create!(entry_date: date, period_id: period.id, currency_code: currency, exchange_rate: rate,
                                 memo:, reference:, status: "posted", posted_at: Time.now.utc,
                                 reverses_entry_id: reverses, is_closing: closing)
    JournalLine.insert_all!(lines.each.with_index(1).map do |l, i|
      l.to_h.merge(journal_entry_id: entry.id, line_no: i)
    end)
    entry
  end

  # A line for a signed amount on its natural side; a negative amount goes
  # on the opposite side (domain §4.3).
  def side(amount, base, debit, memo, account)
    if amount.positive? == debit
      Line.new(account, amount.abs, ZERO, base.abs, ZERO, memo)
    else
      Line.new(account, ZERO, amount.abs, ZERO, base.abs, memo)
    end
  end

  # -- Invoices, bills, credit notes ------------------------------------------------

  def post_document(kind, id)
    doc = kind.model.lock.find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")
    raise ApiError::Conflict, "#{kind.noun} is #{doc.status}, not draft" if doc.status != "draft"
    raise ApiError::Unprocessable, "#{kind.noun} total must be greater than zero" unless doc.total.positive?

    control = kind.party_model.where(id: doc[kind.party_id]).pick(kind.control_account)
    if control.nil?
      raise ApiError::Unprocessable, "the #{kind.party} has no #{kind.sales ? 'A/R' : 'A/P'} control account"
    end

    lk = kind.lines
    lines = lk.model.where(lk.parent_id => id).order(:line_no).to_a
    fallback = kind.sales ? :revenue_account_id : :inventory_account_id
    products = Product.where(id: lines.filter_map(&:product_id)).pluck(:id, fallback).to_h
    taxes = TaxCode.where(code: lines.filter_map(&:tax_code)).pluck(:code, :tax_account_id).to_h

    detail = Hash.new(ZERO)
    tax = Hash.new(ZERO)
    lines.each do |line|
      account = line[lk.account] || (line.product_id && products[line.product_id])
      unless line.line_subtotal.zero?
        if account.nil?
          raise ApiError::Unprocessable, "line #{line.line_no} has no #{kind.sales ? 'revenue' : 'expense'} account"
        end

        detail[account] += line.line_subtotal
      end
      next if line.tax_amount.zero?

      tax_account = taxes[line.tax_code]
      raise ApiError::Unprocessable, "line #{line.line_no} is taxed but its tax code has no tax account" if tax_account.nil?

      tax[tax_account] += line.tax_amount
    end

    date = doc[kind.date]
    period = Calendar.period_for_posting(date)
    rate = rate_for(doc.currency_code, date)

    # Detail lines sit opposite the control line.
    entries = []
    [[kind.sales ? "Revenue" : "Expense", detail], [kind.sales ? "Sales tax" : "Input tax", tax]].each do |memo, sums|
      sums.sort.each do |account, amount|
        entries << side(amount, Values.round4(amount * rate), !kind.control_debit, memo, account) unless amount.zero?
      end
    end
    # The control line carries the total; its base is the net of the details' (domain §7.2).
    base_net = entries.sum(ZERO) { |e| kind.control_debit ? e.base_credit - e.base_debit : e.base_debit - e.base_credit }
    control_memo = kind.sales ? "Accounts receivable" : "Accounts payable"
    control_line = if kind.control_debit
      Line.new(control, doc.total, ZERO, base_net, ZERO, control_memo)
    else
      Line.new(control, ZERO, doc.total, ZERO, base_net, control_memo)
    end

    number = doc[kind.number]
    entry = new_entry(date, doc.currency_code, [control_line, *entries], memo: "#{kind.label} #{number}",
                                                                          reference: number, rate:, period:)
    kind.model.where(id:).update_all(status: "posted", journal_entry_id: entry.id, period_id: period.id)
    entry.id
  end

  def unpost_document(kind, id)
    doc = kind.model.lock.find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")
    raise ApiError::Conflict, "#{kind.noun} is not posted" if doc.status != "posted" || doc.journal_entry_id.nil?

    if kind.credit
      if kind.applications.where(credit_note_id: id).exists?
        raise ApiError::Conflict, "the #{kind.noun} has been applied and cannot be unposted"
      end
    elsif applied_to?(kind, id)
      raise ApiError::Conflict, "payments or credit notes are applied to this #{kind.noun}; it cannot be unposted"
    end
    reversal = reverse_entry(doc.journal_entry_id)
    kind.model.where(id:).update_all(status: "draft", journal_entry_id: nil, period_id: nil)
    reversal.id
  end

  def applied_to?(kind, id)
    column = kind.sales ? "invoice_id" : "bill_id"
    Kinds.settlers(kind.sales).any? { |settler| settler.applications.where(column => id).exists? }
  end

  # Post the mirror of an entry: same date, currency, and rate, every line's
  # sides swapped (domain §4.4).
  def reverse_entry(entry_id)
    original = JournalEntry.find(entry_id)
    if JournalEntry.where(reverses_entry_id: entry_id).exists?
      raise ApiError::Conflict, "journal entry #{entry_id} is already reversed"
    end
    if BankStatementLine.joins(:journal_line).where(journal_lines: { journal_entry_id: entry_id }).exists?
      raise ApiError::Conflict, "journal entry #{entry_id} has lines matched on a bank statement"
    end

    lines = original.lines.map { |l| Line.new(l.account_id, l.credit, l.debit, l.base_credit, l.base_debit, l.memo) }
    new_entry(original.entry_date, original.currency_code, lines, memo: "Reversal of journal entry #{entry_id}",
                                                                  reference: original.reference, rate: original.exchange_rate,
                                                                  reverses: entry_id, closing: original.is_closing)
  end

  # -- Payments ------------------------------------------------------------------

  def post_payment(kind, id)
    p = kind.model.lock.find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")
    raise ApiError::Conflict, "#{kind.noun} is #{p.status}, not draft" if p.status != "draft"
    raise ApiError::Unprocessable, "amount must be greater than zero" unless p.amount.positive?

    cash = p[kind.cash_account]
    raise ApiError::Unprocessable, "the payment has no #{kind.sales ? 'deposit' : 'payment'} account" if cash.nil?

    control = kind.party_model.where(id: p[kind.party_id]).pick(kind.control_account)
    if control.nil?
      raise ApiError::Unprocessable, "the #{kind.party} has no #{kind.sales ? 'A/R' : 'A/P'} control account"
    end

    period = Calendar.period_for_posting(p.payment_date)
    rate = rate_for(p.currency_code, p.payment_date)
    base = Values.round4(p.amount * rate)
    lines = if kind.sales
      [Line.new(cash, p.amount, ZERO, base, ZERO, "Cash received"),
       Line.new(control, ZERO, p.amount, ZERO, base, "Accounts receivable")]
    else
      [Line.new(control, p.amount, ZERO, base, ZERO, "Accounts payable"),
       Line.new(cash, ZERO, p.amount, ZERO, base, "Cash paid")]
    end
    memo = kind.sales ? "Customer payment" : "Supplier payment"
    entry = new_entry(p.payment_date, p.currency_code, lines, memo:, rate:, period:)
    kind.model.where(id:).update_all(status: "posted", journal_entry_id: entry.id, period_id: period.id)
    entry.id
  end

  def unpost_payment(kind, id)
    p = kind.model.lock.find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")
    raise ApiError::Conflict, "#{kind.noun} is not posted" if p.status != "posted" || p.journal_entry_id.nil?

    reversal = reverse_entry(p.journal_entry_id)
    apps = kind.applications.where(payment_id: id)
    apps.where.not(fx_journal_entry_id: nil).pluck(:fx_journal_entry_id).each { reverse_entry(_1) }
    apps.delete_all
    kind.model.where(id:).update_all(status: "draft", journal_entry_id: nil, period_id: nil)
    reversal.id
  end

  # -- Stock movements -------------------------------------------------------------

  def post_movement(id, credit_account_id)
    sm = StockMovement.lock.find_by(id:) || raise(ApiError::NotFound, "stock movement not found")
    raise ApiError::Conflict, "stock movement is already posted" if sm.journal_entry_id
    unless %w[receipt issue].include?(sm.movement_type)
      raise ApiError::Unprocessable, "#{sm.movement_type} movements do not post to the ledger"
    end
    raise ApiError::Unprocessable, "the movement has no cost to post" if sm.total_cost.zero?

    product = sm.product
    cost = sm.total_cost.abs
    if sm.movement_type == "issue"
      if product.cogs_account_id.nil? || product.inventory_account_id.nil?
        raise ApiError::Unprocessable, "the product needs both a COGS and an inventory account"
      end

      lines = [Line.new(product.cogs_account_id, cost, ZERO, cost, ZERO, "Cost of goods sold"),
               Line.new(product.inventory_account_id, ZERO, cost, ZERO, cost, "Inventory")]
      memo = "Inventory issue"
    else
      raise ApiError::Unprocessable, "the product has no inventory account" if product.inventory_account_id.nil?
      unless credit_account_id && Account.exists?(id: credit_account_id, is_postable: true, is_active: true)
        raise ApiError::Unprocessable, "credit_account_id must name a postable, active account"
      end

      lines = [Line.new(product.inventory_account_id, cost, ZERO, cost, ZERO, "Inventory"),
               Line.new(credit_account_id, ZERO, cost, ZERO, cost, "Goods received not invoiced")]
      memo = "Inventory receipt"
    end
    period = Calendar.period_for_posting(sm.movement_date)
    entry = new_entry(sm.movement_date, base_currency, lines, memo:, rate: BigDecimal(1), period:)
    StockMovement.where(id:).update_all(journal_entry_id: entry.id, period_id: period.id)
    entry.id
  end

  def unpost_movement(id)
    sm = StockMovement.lock.find_by(id:) || raise(ApiError::NotFound, "stock movement not found")
    raise ApiError::Conflict, "stock movement is not posted" if sm.journal_entry_id.nil?

    reversal = reverse_entry(sm.journal_entry_id)
    StockMovement.where(id:).update_all(journal_entry_id: nil, period_id: nil)
    reversal.id
  end
end
