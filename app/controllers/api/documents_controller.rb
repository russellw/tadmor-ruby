module Api
  # Invoices, bills, and credit notes (spec/api.md §5.9).
  class DocumentsController < BaseController
    admin_only only: :unpost

    def index = ok(Documents.list_documents(kind))
    def show = ok(Documents.document_json(kind, Documents.get_document(kind, id)))
    def create = created(id: Documents.create(kind, body, current_user))

    def update
      Documents.update(kind, id, body)
      no_content
    end

    def destroy
      Documents.delete(kind, id)
      no_content
    end

    def lines = ok(Documents.list_lines(kind, id))
    def applications = ok(Documents.credit_note_applications(kind, id))
    def post = ok(journal_entry_id: Posting.post_document(kind, id))
    def unpost = ok(reversal_entry_id: Posting.unpost_document(kind, id))
    def apply = ok(applications: Settlement.apply(kind.collection, id))

    private

    def kind = Kinds::DOCUMENTS.fetch(path_param(:collection))
  end
end
