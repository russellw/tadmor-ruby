module Api
  # Customer and supplier payments (spec/api.md §5.9).
  class PaymentsController < BaseController
    admin_only only: :unpost

    def index = ok(Documents.list_payments(kind))
    def show = ok(Documents.payment_json(kind, Documents.get_payment(kind, id)))
    def create = created(id: Documents.create_payment(kind, body, current_user))

    def update
      Documents.update_payment(kind, id, body)
      no_content
    end

    def destroy
      Documents.delete_payment(kind, id)
      no_content
    end

    def applications = ok(Documents.payment_applications(kind, id))
    def post = ok(journal_entry_id: Posting.post_payment(kind, id))
    def unpost = ok(reversal_entry_id: Posting.unpost_payment(kind, id))
    def apply = ok(applications: Settlement.apply(kind.collection, id))

    private

    def kind = Kinds::PAYMENTS.fetch(path_param(:collection))
  end
end
