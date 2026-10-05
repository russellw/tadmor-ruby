# Fiscal years and accounting periods (spec/api.md §5.7, domain §9.1–9.2).
module Calendar
  module_function

  def fiscal_year_json(y)
    { "id" => y.id, "name" => y.name, "start_date" => Values.fmt_date(y.start_date),
      "end_date" => Values.fmt_date(y.end_date), "status" => y.status }
  end

  def period_json(p)
    { "id" => p.id, "fiscal_year_id" => p.fiscal_year_id, "name" => p.name,
      "start_date" => Values.fmt_date(p.start_date), "end_date" => Values.fmt_date(p.end_date), "status" => p.status }
  end

  def dates(b)
    start = Values.parse_date(b.required_str("start_date"), "start_date")
    finish = Values.parse_date(b.required_str("end_date"), "end_date")
    raise ApiError::Unprocessable, "end_date must not be before start_date" if finish < start

    [start, finish]
  end

  def list_fiscal_years = FiscalYear.order(:start_date, :id).map { fiscal_year_json(_1) }
  def get_fiscal_year(id) = FiscalYear.find_by(id:) || raise(ApiError::NotFound, "fiscal year not found")

  def create_fiscal_year(b)
    name = b.required_str("name")
    b.required_str("start_date")
    b.required_str("end_date")
    start, finish = dates(b)
    FiscalYear.create!(name:, start_date: start, end_date: finish).id
  end

  def update_fiscal_year(id, b)
    name = b.required_str("name")
    b.required_str("start_date")
    b.required_str("end_date")
    get_fiscal_year(id)
    start, finish = dates(b)
    FiscalYear.where(id:).update_all(name:, start_date: start, end_date: finish)
  end

  def list_periods = AccountingPeriod.order(:start_date, :id).map { period_json(_1) }
  def get_period(id) = AccountingPeriod.find_by(id:) || raise(ApiError::NotFound, "accounting period not found")

  def period_required(b)
    b.required_id("fiscal_year_id")
    b.required_str("name")
    b.required_str("start_date")
    b.required_str("end_date")
  end

  def create_period(b)
    period_required(b)
    start, finish = dates(b)
    year = FiscalYear.find_by(id: b.int("fiscal_year_id"))
    raise ApiError::Unprocessable, "unknown fiscal_year_id" if year.nil?
    raise ApiError::Unprocessable, "the fiscal year is closed" if year.status != "open"

    AccountingPeriod.create!(fiscal_year_id: year.id, name: b.str("name"), start_date: start, end_date: finish).id
  end

  def update_period(id, b)
    period_required(b)
    get_period(id)
    start, finish = dates(b)
    status = b.text("status") || "open"
    raise ApiError::Unprocessable, "status must be open or closed" unless %w[open closed].include?(status)

    AccountingPeriod.where(id:).update_all(fiscal_year_id: b.int("fiscal_year_id"), name: b.str("name"),
                                           start_date: start, end_date: finish, status:)
  end

  # The month after the latest period, for the new-period form (domain §13 A1).
  def next_period_proposal
    last = AccountingPeriod.order(end_date: :desc).first
    return nil if last.nil?

    start = last.end_date + 1
    finish = start.end_of_month
    year = FiscalYear.where(start_date: ..start, end_date: start..).first
    finish = [finish, year.end_date].min if year
    { "fiscal_year_id" => year&.id, "name" => start.strftime("%Y-%m"), "start_date" => start.iso8601,
      "end_date" => finish.iso8601 }
  end

  # The open period covering a date, creating a monthly one if needed (domain §9.2).
  def period_for_posting(date)
    covering = AccountingPeriod.where(start_date: ..date, end_date: date..).first
    if covering
      raise ApiError::Unprocessable, "the accounting period covering #{date} is closed" if covering.status != "open"

      return covering
    end
    year = FiscalYear.where(start_date: ..date, end_date: date.., status: "open").first
    raise ApiError::Unprocessable, "no open accounting period or fiscal year covers #{date}" if year.nil?

    begin
      AccountingPeriod.transaction(requires_new: true) do
        AccountingPeriod.create!(fiscal_year_id: year.id, name: date.strftime("%Y-%m"),
                                 start_date: [date.beginning_of_month, year.start_date].max,
                                 end_date: [date.end_of_month, year.end_date].min)
      end
    rescue ActiveRecord::StatementInvalid
      raise ApiError::Unprocessable, "cannot create a period for #{date}: it would overlap an existing period"
    end
  end
end
