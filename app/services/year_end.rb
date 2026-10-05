# Year-end close and reopen (domain §9.3).
module YearEnd
  ZERO = Values::ZERO

  module_function

  def lock_year(id) = FiscalYear.lock.find_by(id:) || raise(ApiError::NotFound, "fiscal year not found")

  # The same date a year later; 29 February becomes 28 February.
  def plus_year(d) = d.next_year

  # Each revenue and expense account's non-zero base balance (debit-positive) up to a date.
  def income_balances(end_date)
    Reports.rows(<<~SQL, end_date).map { [_1["account_id"], _1["balance"]] }
      SELECT jl.account_id, sum(jl.base_debit - jl.base_credit) AS balance
      FROM journal_lines jl
      JOIN journal_entries je ON je.id = jl.journal_entry_id
      JOIN accounts a ON a.id = jl.account_id
      WHERE je.status = 'posted' AND a.account_type IN ('revenue', 'expense') AND je.entry_date <= ?
      GROUP BY jl.account_id HAVING sum(jl.base_debit - jl.base_credit) <> 0
      ORDER BY jl.account_id
    SQL
  end

  def close(id, retained_earnings_id)
    year = lock_year(id)
    raise ApiError::Conflict, "fiscal year #{year.name} is not open" if year.status != "open"
    if FiscalYear.where(status: "open", start_date: ...year.start_date).where.not(id:).exists?
      raise ApiError::Unprocessable, "an earlier fiscal year is still open"
    end
    unless Account.exists?(id: retained_earnings_id, is_postable: true, is_active: true, account_type: "equity")
      raise ApiError::Unprocessable, "the retained earnings account must be a postable, active equity account"
    end

    closing_id = nil
    balances = income_balances(year.end_date)
    if balances.any?
      period = AccountingPeriod.where(start_date: ..year.end_date, end_date: year.end_date..).first
      if period.nil?
        period = Calendar.period_for_posting(year.end_date)
      elsif period.status == "closed"
        AccountingPeriod.where(id: period.id).update_all(status: "open")
      end
      lines = balances.map do |account, bal|
        Posting::Line.new(account, [-bal, ZERO].max, [bal, ZERO].max, [-bal, ZERO].max, [bal, ZERO].max, "Year-end close")
      end
      net = balances.sum(ZERO) { |_, bal| bal } # debit-positive: a net loss is positive
      unless net.zero?
        lines << Posting::Line.new(retained_earnings_id, [net, ZERO].max, [-net, ZERO].max, [net, ZERO].max,
                                   [-net, ZERO].max, "Net income (loss) for #{year.name}")
      end
      closing_id = Posting.new_entry(year.end_date, Posting.base_currency, lines, memo: "Year-end close #{year.name}",
                                                                                  reference: year.name, rate: BigDecimal(1),
                                                                                  closing: true, period:).id
    end

    AccountingPeriod.where(fiscal_year_id: id, status: "open").update_all(status: "closed")
    FiscalYear.where(id:).update_all(status: "closed", closing_entry_id: closing_id)

    next_id = nil
    start = year.end_date + 1
    finish = plus_year(start) - 1
    name = "FY#{finish.year}"
    if !FiscalYear.where(start_date: ..start, end_date: start..).exists? && !FiscalYear.exists?(name:)
      next_id = FiscalYear.create!(name:, start_date: start, end_date: finish).id
    end
    { "closing_entry_id" => closing_id, "next_fiscal_year_id" => next_id }
  end

  def reopen(id)
    year = lock_year(id)
    raise ApiError::Conflict, "fiscal year #{year.name} is not closed" if year.status != "closed"
    if FiscalYear.where(status: "closed").where("start_date > ?", year.start_date).exists?
      raise ApiError::Unprocessable, "a later fiscal year is closed"
    end

    FiscalYear.where(id:).update_all(status: "open", closing_entry_id: nil)
    return nil if year.closing_entry_id.nil?

    period_id = JournalEntry.where(id: year.closing_entry_id).pick(:period_id)
    AccountingPeriod.where(id: period_id, status: "closed").update_all(status: "open")
    Posting.reverse_entry(year.closing_entry_id).id
  end
end
