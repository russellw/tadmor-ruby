module Api
  # Sales and purchase orders (spec/api.md §5.10).
  class OrdersController < BaseController
    def index = ok(Orders.list(kind))
    def show = ok(Orders.order_json(kind, Orders.get(kind, id)))
    def create = created(id: Documents.create(kind, body, current_user))

    def update
      Documents.update(kind, id, body)
      no_content
    end

    def destroy
      Documents.delete(kind, id)
      no_content
    end

    def lines = ok(Orders.lines(kind, id))

    def transition
      Orders.public_send(path_param(:transition), kind, id)
      no_content
    end

    # Invoice a sales order, or bill a purchase order.
    def bill = created("#{kind.document.noun}_id" => Orders.invoice(kind, id, body, current_user))

    # Ship a sales order, or receive a purchase order.
    def move = created(movement_ids: Orders.move(kind, id, body, current_user))

    private

    def kind = Kinds::ORDERS.fetch(path_param(:collection))
  end
end
