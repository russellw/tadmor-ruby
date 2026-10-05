module Ui
  # Customer and supplier payments (domain §13.5, P1–P4).
  class PaymentsController < BaseController
    def index
      names = kind.party_model.joins(:organization).pluck(:id, "organizations.name").to_h
      rows = Documents.list_payments(kind).each { _1["party_name"] = names[_1[kind.party_id]] }
      list_page(
        title: kind.sales ? "Customer payments" : "Supplier payments", rows:,
        columns: [Column.of("Date", "payment_date"), Column.of(kind.sales ? "Customer" : "Supplier", "party_name"),
                  Column.of("Method", "method", kind: "label"), Column.of("Currency", "currency_code"),
                  Column.of("Amount", "amount", numeric: true, kind: "amount"),
                  Column.of("Applied", "amount_applied", numeric: true, kind: "amount"),
                  Column.of("Unapplied", "unapplied", numeric: true, kind: "amount"), Column.of("Status", "status", kind: "status")],
        link: ->(r) { "/#{c}/#{r['id']}" }, new: ["/#{c}/new", "New #{kind.noun}"],
      )
    end

    def new
      party = params[:party].to_s
      initial = { "payment_date" => Values.today.iso8601, "currency_code" => Posting.base_currency,
                  kind.party_id => party.match?(/\A\d+\z/) ? party.to_i : nil }
      crud_form(title: "New #{kind.noun}", fields:, initial:, back: "/#{c}", done: ->(new_id) { "/#{c}/#{new_id}" }) do |b|
        Documents.create_payment(kind, b, current_user)
      end
    end

    def edit
      payment_id = id
      initial = Documents.payment_json(kind, Documents.get_payment(kind, payment_id))
      crud_form(title: "Edit #{kind.noun}", fields:, initial:, back: detail_path, done: ->(_) { detail_path }) do |b|
        Documents.update_payment(kind, payment_id, b)
      end
    end

    def show = detail

    def destroy
      Documents.get_payment(kind, id)
      error = nil
      if request.post?
        _, error = attempt { Documents.delete_payment(kind, id) }
        return redirect_to("/#{c}") if error.nil?
      end
      page "ui/confirm", title: "Delete #{kind.noun} #{id}?", error:, back: detail_path,
                         question: "This deletes the draft #{kind.noun}. It cannot be undone."
    end

    def post = act(:post) { Posting.post_payment(kind, id) }
    def unpost = act(:unpost, admin: true) { Posting.unpost_payment(kind, id) }
    def apply = act(:apply) { Settlement.apply(c, id) }

    private

    def c = params[:collection]
    def kind = Kinds::PAYMENTS.fetch(c)
    def detail_path = "/#{c}/#{id}"

    def fields
      [Field.of(kind.party_id, kind.sales ? "Customer" : "Supplier", "ref",
                kind.sales ? Choices.customers : Choices.suppliers, required: true),
       Field.of("payment_date", "Date", "date", required: true),
       Field.of("currency_code", "Currency", "select", Choices.currencies, required: true),
       Field.of("amount", "Amount", "decimal", required: true),
       Field.of("method", "Method", "select", Choices.static(*Kinds::PAYMENT_METHODS.map { [_1, _1.capitalize] })),
       Field.of("reference", "Reference"),
       Field.of(kind.cash_account, kind.sales ? "Deposit account" : "Payment account", "ref", Choices.postable_accounts,
                help: "The cash or bank account; posting needs it.")]
    end

    def detail(errors = {})
      p = Documents.get_payment(kind, id)
      pj = Documents.payment_json(kind, p)
      apps = Documents.payment_applications(kind, id).each { _1["url"] = "/#{kind.documents.collection}/#{_1['document_id']}" }
      account = Account.find_by(id: pj[kind.cash_account])
      page "ui/payment_detail", title: "#{kind.noun.capitalize} #{id}", kind:, c:, p: pj, applications: apps,
                                party: p.public_send(kind.party).organization.name,
                                cash_label: kind.sales ? "Deposit account" : "Payment account",
                                cash_account: account && "#{account.code} #{account.name}", errors:
    end
  end
end
