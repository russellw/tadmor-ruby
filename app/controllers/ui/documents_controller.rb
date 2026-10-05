module Ui
  # Invoices, bills, sales credit notes, and supplier credits (domain §13.4,
  # D1–D7). The route names the collection.
  class DocumentsController < BaseController
    include LineItemForm

    PLURAL = { "sales-invoices" => "Invoices", "purchase-bills" => "Bills", "sales-credit-notes" => "Credit notes",
               "purchase-credit-notes" => "Supplier credits" }.freeze
    SINGULAR = { "sales-invoices" => "invoice", "purchase-bills" => "bill", "sales-credit-notes" => "credit note",
                 "purchase-credit-notes" => "supplier credit" }.freeze

    def index
      names = kind.party_model.joins(:organization).pluck(:id, "organizations.name").to_h
      rows = Documents.list_documents(kind).each { _1["party_name"] = names[_1[kind.party_id]] }
      columns = [Column.of("Number", kind.number), Column.of(kind.sales ? "Customer" : "Supplier", "party_name"),
                 Column.of("Date", kind.date)]
      columns << Column.of("Due", "due_date") if kind.due_date
      columns += [Column.of("Currency", "currency_code"), Column.of("Total", "total", numeric: true, kind: "amount"),
                  Column.of(kind.credit ? "Unapplied" : "Balance", "balance", numeric: true, kind: "amount"),
                  Column.of("Status", "status", kind: "status"),
                  Column.of(kind.credit ? "Application" : "Payment", kind.status_field, kind: "status")]
      list_page(title: PLURAL[c], rows:, columns:, link: ->(r) { "/#{c}/#{r['id']}" }, new: ["/#{c}/new", "New #{singular}"])
    end

    def new
      party = params[:party].to_s
      initial = { kind.date => Values.today.iso8601, "currency_code" => Posting.base_currency,
                  kind.party_id => party.match?(/\A\d+\z/) ? party.to_i : nil }
      document_form(kind, title: "New #{singular}", initial:, initial_lines: [], back: "/#{c}") do |b|
        Documents.create(kind, b, current_user)
      end
    end

    def edit
      doc_id = id
      doc = Documents.document_json(kind, Documents.get_document(kind, doc_id))
      document_form(kind, title: "Edit #{singular} #{doc[kind.number]}", initial: doc,
                          initial_lines: Documents.list_lines(kind, doc_id), back: detail_path) do |b|
        Documents.update(kind, doc_id, b)
        doc_id
      end
    end

    def show = detail

    def destroy
      doc = Documents.document_json(kind, Documents.get_document(kind, id))
      error = nil
      if request.post?
        _, error = attempt { Documents.delete(kind, id) }
        return redirect_to("/#{c}") if error.nil?
      end
      page "ui/confirm", title: "Delete #{singular} #{doc[kind.number]}?", error:, back: detail_path,
                         question: "This deletes draft #{singular} #{doc[kind.number]} and its lines. It cannot be undone."
    end

    def post = act(:post) { Posting.post_document(kind, id) }
    def unpost = act(:unpost, admin: true) { Posting.unpost_document(kind, id) }
    def apply = act(:apply) { Settlement.apply(c, id) }

    def email
      return redirect_to(detail_path) unless request.post?

      sent, error = attempt { Printing.email(c, id, email_recipients) }
      error ? detail(email: error) : detail({}, sent)
    end

    private

    def c = params[:collection]
    def kind = Kinds::DOCUMENTS.fetch(c)
    def singular = SINGULAR[c]
    def detail_path = "/#{c}/#{id}"

    def detail(errors = {}, email_result = nil)
      d = Documents.get_document(kind, id)
      doc = Documents.document_json(kind, d)
      lines = Documents.list_lines(kind, id)
      applied = if kind.credit
        target = kind.sales ? Kinds::SALES_INVOICE : Kinds::PURCHASE_BILL
        Documents.credit_note_applications(kind, id).each { _1["url"] = "/#{target.collection}/#{_1['document_id']}" }
      else
        Documents.applications_to(kind, id).each { _1["url"] = "/#{_1['collection']}/#{_1['id']}" }
      end
      party = d.public_send(kind.party)
      page "ui/document_detail", title: "#{kind.label} #{doc[kind.number]}", kind:, c:, doc:, lines:, applied:,
                                 party: party.organization.name, party_url: "/#{kind.party}s/#{party.id}",
                                 subtotal: d.subtotal, tax_total: d.tax_total,
                                 order_linked: lines.any? { _1["order_line_id"] },
                                 can_apply: kind.credit && doc["status"] == "posted" && BigDecimal(doc["balance"]).positive?,
                                 errors:, email_result:
    end
  end
end
