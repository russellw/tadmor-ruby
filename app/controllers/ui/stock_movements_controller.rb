module Ui
  # Stock movements (domain §13.7, S1–S3).
  class StockMovementsController < BaseController
    TYPE_LABELS = [["receipt", "Receipt (in)"], ["issue", "Issue (out)"], ["adjustment", "Adjustment (signed as typed)"],
                   ["transfer_in", "Transfer in"], ["transfer_out", "Transfer out"]].freeze

    def index
      products = Product.pluck(:id, :sku).to_h
      warehouses = Warehouse.pluck(:id, :code).to_h
      rows = Stock.list.each do |r|
        r["product"] = products[r["product_id"]]
        r["warehouse"] = warehouses[r["warehouse_id"]]
      end
      list_page(
        title: "Stock movements", rows:,
        columns: [Column.of("Date", "movement_date"), Column.of("Product", "product"), Column.of("Warehouse", "warehouse"),
                  Column.of("Type", "movement_type", kind: "status"), Column.of("Quantity", "quantity", numeric: true, kind: "qty"),
                  Column.of("Unit cost", "unit_cost", numeric: true, kind: "amount"),
                  Column.of("Total cost", "total_cost", numeric: true, kind: "amount"),
                  Column.of("Posted", ->(r) { r["status"] == "posted" }, kind: "bool")],
        link: ->(r) { "/stock-movements/#{r['id']}" }, new: ["/stock-movements/new", "New stock movement"],
      )
    end

    def new
      crud_form(title: "New stock movement", fields:, initial: { "movement_date" => Values.today.iso8601 },
                back: "/stock-movements", done: ->(new_id) { "/stock-movements/#{new_id}" }) do |b|
        Stock.create(signed(b), current_user)
      end
    end

    def edit
      movement_id = id
      initial = Stock.json(Stock.get(movement_id))
      initial["quantity"] = Printing.qty(BigDecimal(initial["quantity"]).abs) unless initial["movement_type"] == "adjustment"
      crud_form(title: "Edit stock movement #{movement_id}", fields:, initial:, back: detail_path,
                done: ->(_) { detail_path }) { Stock.update(movement_id, signed(_1)) }
    end

    def show = detail

    def destroy
      Stock.get(id)
      error = nil
      if request.post?
        _, error = attempt { Stock.delete(id) }
        return redirect_to("/stock-movements") if error.nil?
      end
      page "ui/confirm", title: "Delete stock movement #{id}?", error:, back: detail_path,
                         question: "This deletes the unposted movement. A movement made by order fulfilment " \
                                   "returns its quantity to the order."
    end

    def post
      raw = params[:credit_account_id].to_s
      act(:post) { Posting.post_movement(id, raw.match?(/\A\d+\z/) ? raw.to_i : nil) }
    end

    def unpost = act(:unpost, admin: true) { Posting.unpost_movement(id) }

    private

    def detail_path = "/stock-movements/#{id}"

    def fields
      [Field.of("product_id", "Product", "ref", Choices.products(track_inventory: true), required: true,
                help: "Only active, inventory-tracked products."),
       Field.of("warehouse_id", "Warehouse", "ref", Choices.warehouses, required: true),
       Field.of("movement_type", "Type", "select", Choices.static(*TYPE_LABELS), required: true),
       Field.of("movement_date", "Date", "date"),
       Field.of("quantity", "Quantity", "decimal", required: true,
                help: "Enter the amount moved; receipts add stock and issues remove it. An adjustment keeps the sign you type."),
       Field.of("unit_cost", "Unit cost", "decimal"),
       Field.of("reference", "Reference"),
       Field.of("notes", "Notes", "textarea")]
    end

    # S2: the quantity is entered as a magnitude and signed by the type.
    def signed(body)
      type, q = body.data["movement_type"], body.data["quantity"]
      if q.is_a?(String) && Values::DECIMAL.match?(q) && (Stock::POSITIVE + Stock::NEGATIVE).include?(type)
        magnitude = q.delete_prefix("-").delete_prefix("+")
        body.data["quantity"] = Stock::NEGATIVE.include?(type) ? "-#{magnitude}" : magnitude
      end
      body
    end

    def detail(errors = {})
      sm = Stock.get(id)
      page "ui/movement_detail", title: "Stock movement #{id}", m: Stock.json(sm), product: sm.product,
                                 warehouse: sm.warehouse, credit_choices: Choices.postable_accounts.call,
                                 default_credit: params[:credit_account_id].presence || Account.find_by(code: "2150")&.id,
                                 errors:
    end
  end
end
