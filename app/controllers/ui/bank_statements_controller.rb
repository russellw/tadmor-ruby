module Ui
  # Bank statements and reconciliation (domain §13.9, A4–A5).
  class BankStatementsController < BaseController
    FIELDS = [
      Field.of("account_id", "Cash account", "ref", Choices.accounts(is_postable: true, is_cash: true), required: true),
      Field.of("statement_date", "Statement date", "date", required: true),
      Field.of("opening_balance", "Opening balance", "decimal", required: true),
      Field.of("closing_balance", "Closing balance", "decimal", required: true),
      Field.of("reference", "Reference"),
    ].freeze

    def index
      list_page(
        title: "Bank statements", rows: Banking.list,
        columns: [Column.of("Date", "statement_date"), Column.of("Account", ->(r) { "#{r['account_code']} #{r['account_name']}" }),
                  Column.of("Reference", "reference"),
                  Column.of("Closing balance", "closing_balance", numeric: true, kind: "amount"),
                  Column.of("Matched", ->(r) { "#{r['matched_count']} of #{r['line_count']}" }, numeric: true),
                  Column.of("Difference", "difference", numeric: true, kind: "amount"), Column.of("Status", "status", kind: "status")],
        link: ->(r) { "/bank-statements/#{r['id']}" }, new: ["/bank-statements/new", "New statement"],
      )
    end

    def new
      crud_form(title: "New bank statement", fields: FIELDS, initial: {}, back: "/bank-statements",
                done: ->(new_id) { "/bank-statements/#{new_id}" }) { Banking.create(_1, current_user) }
    end

    def edit
      statement_id = id
      crud_form(title: "Edit bank statement", fields: FIELDS, initial: Banking.json(Banking.get(statement_id)),
                back: detail_path, done: ->(_) { detail_path }) { Banking.update(statement_id, _1) }
    end

    def show = detail

    def destroy
      s = Banking.json(Banking.get(id))
      error = nil
      if request.post?
        _, error = attempt { Banking.delete(id) }
        return redirect_to("/bank-statements") if error.nil?
      end
      page "ui/confirm", title: "Delete bank statement #{s['reference'] || s['id']}?", error:, back: detail_path,
                         question: "This deletes the statement and all its lines."
    end

    def add_line
      data = %w[txn_date description reference amount].to_h { [_1, params[_1].to_s.strip.presence] }
      statement_action(:add) { Banking.add_line(id, Body.new(data)) }
    end

    def import = statement_action(:import) { Banking.import_csv(id, Body.new("csv" => params[:csv].presence)) }
    def auto_match = statement_action(:auto) { Banking.auto_match(id) }
    def reconcile = statement_action(:reconcile) { Banking.reconcile(id) }

    def reopen
      return detail(reopen: "Only administrators can do this.") unless current_user.is_admin

      statement_action(:reopen) { Banking.reopen(id) }
    end

    def match
      raw = params[:journal_line_id].to_s
      line_action(:match) { Banking.match(line_id, Body.new("journal_line_id" => raw.match?(/\A\d+\z/) ? raw.to_i : nil)) }
    end

    def unmatch = line_action(:unmatch) { Banking.unmatch(line_id) }
    def delete_line = line_action(:delete) { Banking.delete_line(line_id) }

    private

    def detail_path = "/bank-statements/#{id}"
    def line_id = Values.positive_int(params[:line])

    def statement_action(name, &)
      _, error = attempt(&)
      error ? detail({ name => error }, params) : redirect_to(detail_path)
    end

    # Actions addressed to one statement line, which return to its statement.
    def line_action(name, &)
      _, error = attempt(&)
      error ? detail("#{name}-#{line_id}" => error) : redirect_to(detail_path)
    end

    def detail(errors = {}, values = {})
      s = Banking.json(Banking.get(id))
      lines = Banking.lines(id)
      candidates = s["status"] == "open" ? Banking.candidates(id) : []
      lines.each do |line|
        line["error"] = errors.find { |k, _| k.to_s.end_with?("-#{line['id']}") }&.last
        next if line["journal_line_id"]

        amount = BigDecimal(line["amount"])
        line["candidates"] = candidates.select { BigDecimal(_1["amount"]) == amount }
      end
      page "ui/statement_detail", title: "Bank statement #{s['reference'] || s['id']}", s:, lines:,
                                  all_candidates: candidates, errors:, values:
    end
  end
end
