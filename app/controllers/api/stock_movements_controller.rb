module Api
  # Stock movements (spec/api.md §5.12).
  class StockMovementsController < BaseController
    admin_only only: :unpost

    def index = ok(Stock.list)
    def show = ok(Stock.json(Stock.get(id)))
    def create = created(id: Stock.create(body, current_user))

    def update
      Stock.update(id, body)
      no_content
    end

    def destroy
      Stock.delete(id)
      no_content
    end

    def post = ok(journal_entry_id: Posting.post_movement(id, body.int("credit_account_id")))

    def unpost = ok(reversal_entry_id: Posting.unpost_movement(id))
  end
end
