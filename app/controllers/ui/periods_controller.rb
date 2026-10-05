module Ui
  # Fiscal years, periods, and year-end (domain §13.9, A1–A2).
  class PeriodsController < BaseController
    before_action :require_admin, only: %i[close_year reopen_year]

    YEAR_FIELDS = [Field.of("name", "Name", required: true), Field.of("start_date", "Start date", "date", required: true),
                   Field.of("end_date", "End date", "date", required: true)].freeze
    PERIOD_FIELDS = [Field.of("fiscal_year_id", "Fiscal year", "ref", Choices.fiscal_years, required: true),
                     Field.of("name", "Name", required: true), Field.of("start_date", "Start date", "date", required: true),
                     Field.of("end_date", "End date", "date", required: true)].freeze

    def index = periods_page

    # A1: close or reopen a period in one step.
    def toggle
      period_id = id
      p = Calendar.get_period(period_id)
      body = Body.new(Calendar.period_json(p).merge("status" => p.status == "open" ? "closed" : "open"))
      _, error = attempt { Calendar.update_period(period_id, body) }
      error ? periods_page("period-#{period_id}" => error) : redirect_to("/periods")
    end

    def new_year
      last = FiscalYear.order(end_date: :desc).first
      initial = {}
      if last
        start = last.end_date + 1
        finish = YearEnd.plus_year(start) - 1
        initial = { "name" => "FY#{finish.year}", "start_date" => start.iso8601, "end_date" => finish.iso8601 }
      end
      crud_form(title: "New fiscal year", fields: YEAR_FIELDS, initial:, back: "/periods", done: ->(_) { "/periods" }) do |b|
        Calendar.create_fiscal_year(b)
      end
    end

    def edit_year
      year_id = id
      y = Calendar.fiscal_year_json(Calendar.get_fiscal_year(year_id))
      crud_form(title: "Edit fiscal year #{y['name']}", fields: YEAR_FIELDS, initial: y, back: "/periods",
                done: ->(_) { "/periods" }) { Calendar.update_fiscal_year(year_id, _1) }
    end

    def new_period
      initial = Calendar.next_period_proposal || {}
      year = params[:year].to_s
      initial["fiscal_year_id"] = year.to_i if initial.empty? && year.match?(/\A\d+\z/)
      crud_form(title: "New accounting period", fields: PERIOD_FIELDS, initial:, back: "/periods",
                done: ->(_) { "/periods" }) { Calendar.create_period(_1) }
    end

    def edit_period
      period_id = id
      p = Calendar.period_json(Calendar.get_period(period_id))
      fields = PERIOD_FIELDS + [Field.of("status", "Status", "select", Choices.static(%w[open Open], %w[closed Closed]))]
      crud_form(title: "Edit period #{p['name']}", fields:, initial: p, back: "/periods",
                done: ->(_) { "/periods" }) { Calendar.update_period(period_id, _1) }
    end

    # A2: close a year, after saying what will happen.
    def close_year
      year_id = id
      y = Calendar.get_fiscal_year(year_id)
      chosen = params[:retained_earnings_account_id].presence || Account.find_by(code: "3000")&.id
      error = nil
      if request.post?
        raw = params[:retained_earnings_account_id].to_s
        body = Body.new("retained_earnings_account_id" => raw.match?(/\A\d+\z/) ? raw.to_i : nil)
        _, error = attempt { YearEnd.close(year_id, body.required_id("retained_earnings_account_id")) }
        return redirect_to("/periods") if error.nil?
      end
      page "ui/year_close", title: "Close fiscal year #{y.name}", year: y, error:, chosen:,
                            equity_accounts: Choices.accounts(is_postable: true, account_type: "equity").call
    end

    def reopen_year
      year_id = id
      _, error = attempt { YearEnd.reopen(year_id) }
      error ? periods_page("year-#{year_id}" => error) : redirect_to("/periods")
    end

    private

    def periods_page(errors = {})
      years = FiscalYear.order(:start_date).to_a
      periods = AccountingPeriod.order(:start_date).group_by(&:fiscal_year_id)
      page "ui/periods", title: "Periods and year-end", errors:,
                         years: years.map { [_1, periods.fetch(_1.id, [])] },
                         year_error: errors.find { |k, _| k.start_with?("year-") }&.last,
                         closable: years.find { _1.status == "open" },
                         reopenable: years.reverse.find { _1.status == "closed" }
    end
  end
end
