# Printable documents: one shared A4 layout for invoices, bills, credit
# notes, and orders (spec/api.md §5.11, domain §11), and emailing them.
module Printing
  PAGE_W, PAGE_H = Pdf::A4
  MARGIN = 54.0
  RIGHT = PAGE_W - MARGIN
  TOP = PAGE_H - 54
  BOTTOM = 72.0
  NUM_X = MARGIN
  DESC_X = MARGIN + 26
  QTY_X = 360.0
  PRICE_X = 432.0
  TAX_X = 472.0
  DESC_MAX = QTY_X - 60 - DESC_X
  GRAY = 0.45

  # collection => [number label, date label, second-date label, party heading,
  # applied label, balance label]; the title comes from the kind.
  LABELS = {
    "sales-invoices" => ["Invoice no.", "Invoice date", "Due date", "BILL TO", "Amount paid", "Balance due"],
    "purchase-bills" => ["Bill no.", "Bill date", "Due date", "SUPPLIER", "Amount paid", "Balance due"],
    "sales-credit-notes" => ["Credit note no.", "Credit note date", nil, "CREDIT TO", "Amount applied", "Unapplied"],
    "purchase-credit-notes" => ["Credit note no.", "Credit note date", nil, "SUPPLIER", "Amount applied", "Unapplied"],
    "sales-orders" => ["Order no.", "Order date", "Expected ship", "CUSTOMER", nil, nil],
    "purchase-orders" => ["Order no.", "Order date", "Expected receipt", "SUPPLIER", nil, nil],
  }.freeze
  TITLES = { "purchase-credit-notes" => "Supplier Credit" }.freeze

  Party = Data.define(:name, :legal, :tax_id, :address)
  Printable = Data.define(:kind, :number, :status, :currency, :meta, :party_label, :party, :seller, :unit_label,
                          :subtotal, :tax_total, :total, :applied, :balance, :applied_label, :balance_label,
                          :reference, :memo, :lines, :email)

  module_function

  def party(org)
    a = org.addresses.order(:id).first
    lines = []
    if a
      lines = [a.line1, a.line2].compact_blank
      city = [a.city, a.region].compact_blank.join(", ")
      city = "#{city} #{a.postal_code}".strip if a.postal_code.present?
      lines << city if city.present?
      lines << (Country.find_by(code: a.country_code)&.name || a.country_code)
    end
    Party.new(org.name, org.legal_name, org.tax_id, lines)
  end

  # Gather what the printed form of a document shows.
  def load(collection, id)
    number_label, date_label, second_label, party_label, applied_label, balance_label = LABELS.fetch(collection)
    kind = Kinds.printable.fetch(collection)
    if kind.order?
      doc = Orders.get(kind, id)
      lines = Orders.lines(kind, id)
      applied = balance = nil
      title = kind.label
    else
      doc = Documents.get_document(kind, id)
      lines = Documents.list_lines(kind, id)
      applied, balance = doc.bal.amount_applied, doc.bal.balance
      title = TITLES.fetch(collection, kind.label)
    end
    number, date = doc[kind.number_field], doc[kind.date_field]
    second = kind.second_date && doc[kind.second_date]
    org = doc.public_send(kind.party).organization
    meta = [[number_label, number], [date_label, date.iso8601]]
    meta << [second_label, second.iso8601] if second_label && second
    meta << ["Currency", doc.currency_code]
    me = Organization.find_by(is_self: true)
    price = kind.lines.price
    Printable.new(
      kind: title, number:, status: doc.status, currency: doc.currency_code, meta:, party_label:,
      party: party(org), seller: me && party(me), unit_label: price == "unit_price" ? "UNIT PRICE" : "UNIT COST",
      subtotal: doc.subtotal, tax_total: doc.tax_total, total: doc.total, applied:, balance:, applied_label:,
      balance_label:, reference: doc.reference, memo: doc.memo,
      lines: lines.map { |l| l.values_at("line_no", "description", "quantity", price, "tax_rate", "line_subtotal") },
      email: org.email,
    )
  end

  def filename(collection, number)
    "#{Kinds.printable.fetch(collection).pdf_prefix}-#{number.gsub(/[^A-Za-z0-9._-]/, '-')}.pdf"
  end

  # -- Layout ----------------------------------------------------------------------

  # 1234.5 -> "1,234.50": grouped, at least two decimals, none lost.
  def amount(v)
    whole, frac = Values.plain(BigDecimal(v.to_s))
    sign = whole.start_with?("-") ? "-" : ""
    grouped = whole.delete_prefix("-").reverse.scan(/\d{1,3}/).join(",").reverse
    "#{sign}#{grouped}.#{frac.sub(/0+\z/, '').ljust(2, '0')}"
  end

  # A quantity or rate without trailing zeros: "1.5", "3".
  def qty(v) = Values.fmt_rate(BigDecimal(v.to_s))

  def truncate(font, size, limit, s)
    return s if Pdf.width(font, size, s) <= limit

    s = s.chop while !s.empty? && Pdf.width(font, size, "#{s}…") > limit
    "#{s}…"
  end

  def wrap(font, size, limit, s)
    lines = []
    line = ""
    s.split.each do |word|
      candidate = line.empty? ? word : "#{line} #{word}"
      if !line.empty? && Pdf.width(font, size, candidate) > limit
        lines << line
        line = word
      else
        line = candidate
      end
    end
    line.empty? ? lines : lines << line
  end

  def party_text(page, x, y, name_size, p)
    page.text(Pdf::BOLD, name_size, x, y, p.name)
    y -= 13
    if p.legal.present? && p.legal != p.name
      page.text(Pdf::REGULAR, 9, x, y, p.legal, GRAY)
      y -= 12
    end
    p.address.each do |line|
      page.text(Pdf::REGULAR, 9, x, y, line, GRAY)
      y -= 12
    end
    if p.tax_id.present?
      page.text(Pdf::REGULAR, 9, x, y, "Tax ID: #{p.tax_id}", GRAY)
      y -= 12
    end
    y
  end

  def table_header(page, y, unit_label)
    [[NUM_X, "#", false], [DESC_X, "DESCRIPTION", false], [QTY_X, "QTY", true], [PRICE_X, unit_label, true],
     [TAX_X, "TAX %", true], [RIGHT, "AMOUNT", true]].each do |x, label, right|
      page.text(Pdf::BOLD, 8, x - (right ? Pdf.width(Pdf::BOLD, 8, label) : 0), y, label, GRAY)
    end
    y -= 6
    page.line(MARGIN, y, RIGHT, y, 0.8, 0.2)
    y - 14
  end

  def render(d)
    doc = Pdf::Document.new
    page = doc.add_page
    title = d.kind.upcase
    title = "#{d.status.upcase} #{title}" if %w[draft void cancelled].include?(d.status)
    page.text(Pdf::BOLD, 20, RIGHT - Pdf.width(Pdf::BOLD, 20, title), TOP - 6, title)

    meta_y = TOP - 36
    d.meta.each do |label, value|
      page.text(Pdf::REGULAR, 9, RIGHT - 140, meta_y, label, GRAY)
      page.text(Pdf::REGULAR, 9, RIGHT - Pdf.width(Pdf::REGULAR, 9, value), meta_y, value)
      meta_y -= 13
    end

    y = TOP - 6
    y = party_text(page, MARGIN, y, 11, d.seller) if d.seller
    y = [y, meta_y].min - 28
    page.text(Pdf::BOLD, 8, MARGIN, y, d.party_label, GRAY)
    y = party_text(page, MARGIN, y - 14, 10, d.party) - 24

    y = table_header(page, y, d.unit_label)
    d.lines.each do |no, desc, q, unit, rate, subtotal|
      if y < BOTTOM + 20
        page = doc.add_page
        y = table_header(page, TOP, d.unit_label)
      end
      page.text(Pdf::REGULAR, 9, NUM_X, y, no.to_s, GRAY)
      page.text(Pdf::REGULAR, 9, DESC_X, y, truncate(Pdf::REGULAR, 9, DESC_MAX, desc))
      [[QTY_X, qty(q)], [PRICE_X, amount(unit)], [TAX_X, qty(rate)], [RIGHT, amount(subtotal)]].each do |x, s|
        page.text(Pdf::REGULAR, 9, x - Pdf.width(Pdf::REGULAR, 9, s), y, s)
      end
      y -= 6
      page.line(MARGIN, y, RIGHT, y, 0.4, 0.9)
      y -= 12
    end

    if y < BOTTOM + 110
      page = doc.add_page
      y = TOP
    end
    y -= 8
    totals_x = 400.0
    total = lambda do |label, value, font|
      page.text(font, 9, totals_x, y, label)
      page.text(font, 9, RIGHT - Pdf.width(font, 9, value), y, value)
      y -= 14
    end
    total.call("Subtotal", amount(d.subtotal), Pdf::REGULAR)
    total.call("Tax", amount(d.tax_total), Pdf::REGULAR)
    page.line(totals_x, y + 9, RIGHT, y + 9, 0.8, 0.2)
    y -= 2
    total.call("Total", "#{d.currency} #{amount(d.total)}", Pdf::BOLD)
    if d.applied_label && d.applied&.nonzero?
      total.call(d.applied_label, amount(d.applied), Pdf::REGULAR)
      total.call(d.balance_label, "#{d.currency} #{amount(d.balance)}", Pdf::BOLD)
    end

    note_y = y - 14
    if d.reference.present?
      page.text(Pdf::REGULAR, 9, MARGIN, note_y, "Reference: #{d.reference}", GRAY)
      note_y -= 13
    end
    wrap(Pdf::REGULAR, 9, RIGHT - MARGIN, d.memo.to_s).each do |line|
      page.text(Pdf::REGULAR, 9, MARGIN, note_y, line, GRAY)
      note_y -= 13
    end

    doc.pages.each.with_index(1) do |p, i|
      footer = "#{d.kind} #{d.number}  ·  Page #{i} of #{doc.pages.size}"
      p.text(Pdf::REGULAR, 8, (PAGE_W - Pdf.width(Pdf::REGULAR, 8, footer)) / 2, 40, footer, GRAY)
    end
    doc.bytes
  end

  def pdf_for(collection, id)
    d = load(collection, id)
    [render(d), filename(collection, d.number)]
  end

  # -- Email -----------------------------------------------------------------------

  # Send a document's PDF to the given addresses, or to the counterparty's
  # address on file. Returns the addresses used.
  def email(collection, id, to)
    d = load(collection, id)
    if to.empty?
      if d.email.blank?
        raise ApiError::Unprocessable,
              "this counterparty has no email address on file; supply a recipient or set one on the organization"
      end

      to = [d.email]
    end
    bad = to.reject { _1.match?(/\A[^\s@<>,;"]+@[^\s@<>,;"]+\z/) }
    raise ApiError::Unprocessable, "not an email address: #{bad.first}" if bad.any?
    raise ApiError::NotConfigured, "email sending is not configured" if Rails.configuration.x.smtp_addr.blank?

    label = Kinds.printable.fetch(collection).label
    Mailer.deliver(to:, subject: "#{label} #{d.number}", body: "Please find attached #{label.downcase} #{d.number}.",
                   attachment: [filename(collection, d.number), render(d)])
    to
  end
end
