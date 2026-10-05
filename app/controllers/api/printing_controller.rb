module Api
  # PDFs and email (spec/api.md §5.11).
  class PrintingController < BaseController
    def pdf
      data, name = Printing.pdf_for(collection, id)
      # The name is already limited to [A-Za-z0-9._-], so Rails' added
      # filename*= form would say nothing new (spec/api.md §5.11).
      response.headers["Content-Disposition"] = %(inline; filename="#{name}")
      send_data data, type: "application/pdf", disposition: nil
    end

    def email
      to = body.raw("to") || []
      unless to.is_a?(Array) && to.all?(String)
        raise ApiError::BadRequest, "to must be an array of email addresses"
      end

      ok(status: "sent", to: Printing.email(collection, id, to.map(&:strip).reject(&:empty?)))
    end

    private

    def collection = path_param(:collection)
  end
end
