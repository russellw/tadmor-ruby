# Applying payments and credit notes to open documents (domain §5, §7.3).
#
# Auto-apply spreads a settling document's unapplied remainder across the
# party's posted documents in the same currency, oldest first. An
# application posts nothing, except when the two documents' rates value the
# applied amount differently in the base currency: then an FX entry moves
# the difference between the control account and the FX gain/loss account.
# The schema refuses over-application and mismatched parties or currencies.
module Settlement
  ZERO = Values::ZERO

  # For each kind of settler: its kind, the documents it settles, its column
  # in the applications table, its amount field, and its date field.
  Settler = Data.define(:kind, :target, :column, :amount, :date)
  SETTLERS = [
    Settler.new(Kinds::CUSTOMER_PAYMENT, Kinds::SALES_INVOICE, "payment_id", "amount", "payment_date"),
    Settler.new(Kinds::SUPPLIER_PAYMENT, Kinds::PURCHASE_BILL, "payment_id", "amount", "payment_date"),
    Settler.new(Kinds::SALES_CREDIT_NOTE, Kinds::SALES_INVOICE, "credit_note_id", "total", "credit_note_date"),
    Settler.new(Kinds::PURCHASE_CREDIT_NOTE, Kinds::PURCHASE_BILL, "credit_note_id", "total", "credit_note_date"),
  ].index_by { _1.kind.collection }.freeze

  module_function

  def doc_column(target) = target.sales ? "invoice_id" : "bill_id"

  # Everything applied to a document, from payments and credit notes alike.
  def settled(target, doc_id)
    Kinds.settlers(target.sales).sum(ZERO) do |k|
      k.applications.where(doc_column(target) => doc_id).sum(:amount_applied)
    end
  end

  def apply(collection, id)
    s = SETTLERS.fetch(collection)
    kind, target = s.kind, s.target
    settler = kind.model.lock.find_by(id:) || raise(ApiError::NotFound, "#{kind.noun} not found")
    raise ApiError::Conflict, "the #{kind.noun} is not posted" if settler.status != "posted"

    remaining = settler[s.amount] - kind.applications.where(s.column => id).sum(:amount_applied)
    open_docs = target.model.lock.where(kind.party_id => settler[kind.party_id], currency_code: settler.currency_code,
                                        status: "posted").order(target.date, :id)
    created = []
    open_docs.each do |doc|
      break unless remaining.positive?

      available = doc.total - settled(target, doc.id)
      next unless available.positive?

      amount = [available, remaining].min
      app = kind.applications.create!(s.column => id, doc_column(target) => doc.id, amount_applied: amount)
      created << [app, doc]
      remaining -= amount
    end

    post_fx(s, settler, created)
    created.map { |app, doc| { "document_id" => doc.id, "amount_applied" => Values.fmt4(app.amount_applied) } }
  end

  # Post the realized FX entry for each application that needs one.
  def post_fx(s, settler, created)
    return if created.empty?

    kind = s.kind
    settler_rate = JournalEntry.where(id: settler.journal_entry_id).pick(:exchange_rate)
    doc_rates = JournalEntry.where(id: created.map { |_, doc| doc.journal_entry_id }).pluck(:id, :exchange_rate).to_h
    control = kind.party_model.where(id: settler[kind.party_id]).pick(kind.control_account)
    settings = GlSetting.current
    created.each do |app, doc|
      diff = Values.round4(app.amount_applied * settler_rate) - Values.round4(app.amount_applied * doc_rates[doc.journal_entry_id])
      next if diff.zero?

      fx = settings.fx_gain_loss_account_id
      if fx.nil?
        raise ApiError::Unprocessable, "a realized exchange difference arises, but no FX gain/loss account is configured"
      end

      # A/R side: a positive difference debits A/R (a gain); A/P mirrors it.
      v = kind.sales ? diff : -diff
      dr, cr = [v, ZERO].max, [-v, ZERO].max
      lines = [Posting::Line.new(control, dr, cr, dr, cr, "Settlement revaluation"),
               Posting::Line.new(fx, cr, dr, cr, dr, "Exchange gain (loss)")]
      number = doc[s.target.number]
      entry = Posting.new_entry(settler[s.date], settings.base_currency, lines, rate: BigDecimal(1), reference: number,
                                                                                memo: "Exchange difference on settlement of #{s.target.noun} #{number}")
      kind.applications.where(id: app.id).update_all(fx_journal_entry_id: entry.id)
    end
  end
end
