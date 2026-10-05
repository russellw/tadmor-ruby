module Api
  # Bank statements and reconciliation (spec/api.md §5.13).
  class BankStatementsController < BaseController
    admin_only only: :reopen

    def index = ok(Banking.list)
    def show = ok(Banking.json(Banking.get(id)))
    def create = created(id: Banking.create(body, current_user))

    def update
      Banking.update(id, body)
      no_content
    end

    def destroy
      Banking.delete(id)
      no_content
    end

    def lines = ok(Banking.lines(id))

    def add_line = created(id: Banking.add_line(id, body))

    def import = ok(imported: Banking.import_csv(id, body))

    def candidates = ok(Banking.candidates(id))
    def auto_match = ok(matched: Banking.auto_match(id))

    def reconcile
      Banking.reconcile(id)
      no_content
    end

    def reopen
      Banking.reopen(id)
      no_content
    end

    def match
      Banking.match(id, body)
      no_content
    end

    def unmatch
      Banking.unmatch(id)
      no_content
    end

    def delete_line
      Banking.delete_line(id)
      no_content
    end
  end
end
