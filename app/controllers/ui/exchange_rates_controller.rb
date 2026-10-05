module Ui
  # Exchange rates (domain §13.9 A3).
  class ExchangeRatesController < BaseController
    FIELDS = [Field.of("currency_code", "Currency", "select", Choices.currencies, required: true, readonly_on_edit: true),
              Field.of("rate_date", "Date", "date", required: true, readonly_on_edit: true),
              Field.of("rate", "Rate", "decimal", required: true,
                       help: "Base-currency units bought by one unit of this currency.")].freeze

    def index
      list_page(title: "Exchange rates", rows: Master.list_exchange_rates,
                columns: [Column.of("Currency", "currency_code"), Column.of("Date", "rate_date"),
                          Column.of("Rate", "rate", numeric: true)],
                link: ->(r) { "/exchange-rates/#{r['currency_code']}/#{r['rate_date']}" },
                new: ["/exchange-rates/new", "New rate"],
                empty: "No exchange rates. Documents in #{Posting.base_currency} need none.")
    end

    def new
      crud_form(title: "New exchange rate", fields: FIELDS, initial: {}, back: "/exchange-rates",
                done: ->(_) { "/exchange-rates" }) { Master.create_exchange_rate(_1) }
    end

    def edit
      currency, date = params[:currency], params[:date]
      rate = Master.get_exchange_rate(currency, date)
      below = helpers.tag.p(helpers.link_to("Delete this rate", "#{path}/delete"))
      crud_form(title: "#{rate.currency_code} rate on #{date}", fields: FIELDS, initial: Master.exchange_rate_json(rate),
                back: "/exchange-rates", done: ->(_) { "/exchange-rates" }, editing: true, below:) do |b|
        Master.update_exchange_rate(currency, date, b)
      end
    end

    def destroy
      currency, date = params[:currency], params[:date]
      Master.get_exchange_rate(currency, date)
      error = nil
      if request.post?
        _, error = attempt { Master.delete_exchange_rate(currency, date) }
        return redirect_to("/exchange-rates") if error.nil?
      end
      page "ui/confirm", title: "Delete the #{currency} rate for #{date}?", error:, back: path,
                         question: "Entries already posted keep the rate they used."
    end

    private

    def path = "/exchange-rates/#{ERB::Util.url_encode(params[:currency])}/#{ERB::Util.url_encode(params[:date])}"
  end
end
