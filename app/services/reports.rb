# Journal and reports (spec/api.md §5.14, domain §10).
#
# Every figure is a sum of base amounts over posted journal lines. Reports
# are aggregate queries, so they are written in SQL over the shared tables
# and views rather than through Active Record models.
module Reports
  POSTED = <<~SQL.freeze
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_entry_id
    JOIN accounts a ON a.id = jl.account_id
    WHERE je.status = 'posted'
  SQL
  RANGE = "AND (:f::date IS NULL OR je.entry_date >= :f::date) AND (:t::date IS NULL OR je.entry_date <= :t::date)".freeze

  module_function

  # Rows as hashes, with numeric columns as BigDecimal and dates as Date.
  # Binds are positional (?) or named (:name).
  def rows(sql, *binds)
    ActiveRecord::Base.connection.select_all(ActiveRecord::Base.sanitize_sql([sql, *binds])).to_a
  end

  def money(rows, *fields)
    rows.each { |r| fields.each { |f| r[f] = Values.fmt4(r[f]) } }
  end

  def journal_entry(id)
    e = JournalEntry.find_by(id:) || raise(ApiError::NotFound, "journal entry not found")
    { "id" => e.id, "entry_date" => Values.fmt_date(e.entry_date), "currency_code" => e.currency_code,
      "exchange_rate" => Values.fmt_rate(e.exchange_rate), "reference" => e.reference, "memo" => e.memo,
      "status" => e.status, "is_closing" => e.is_closing, "reverses_entry_id" => e.reverses_entry_id,
      "lines" => e.lines.includes(:account).map do |l|
        { "line_no" => l.line_no, "account_id" => l.account_id, "account_code" => l.account.code,
          "account_name" => l.account.name, "memo" => l.memo, "debit" => Values.fmt4(l.debit),
          "credit" => Values.fmt4(l.credit), "base_debit" => Values.fmt4(l.base_debit),
          "base_credit" => Values.fmt4(l.base_credit) }
      end }
  end

  def ledger(account_id, from, to)
    raise ApiError::NotFound, "account not found" unless Account.exists?(account_id)

    result = rows(<<~SQL, a: account_id, f: from, t: to)
      SELECT je.id AS journal_entry_id, je.entry_date, je.reference, COALESCE(jl.memo, je.memo) AS memo,
             je.currency_code, jl.debit, jl.credit, jl.base_debit, jl.base_credit
      FROM journal_lines jl JOIN journal_entries je ON je.id = jl.journal_entry_id
      WHERE jl.account_id = :a AND je.status = 'posted' #{RANGE}
      ORDER BY je.entry_date, je.id, jl.line_no
    SQL
    result.each { |r| r["entry_date"] = Values.fmt_date(r["entry_date"]) }
    money(result, "debit", "credit", "base_debit", "base_credit")
  end

  def trial_balance
    money(rows("SELECT account_id, code, name, account_type, total_debit, total_credit, balance FROM trial_balance ORDER BY code"),
          "total_debit", "total_credit", "balance")
  end

  def profit_and_loss(from, to)
    money(rows(<<~SQL, f: from, t: to), "amount")
      SELECT a.id AS account_id, a.code, a.name, a.account_type,
             sum(CASE WHEN a.account_type = 'revenue' THEN jl.base_credit - jl.base_debit
                      ELSE jl.base_debit - jl.base_credit END) AS amount
      #{POSTED} AND NOT je.is_closing AND a.account_type IN ('revenue', 'expense') #{RANGE}
      GROUP BY a.id ORDER BY a.code
    SQL
  end

  def balance_sheet(as_of)
    result = rows(<<~SQL, d: as_of)
      SELECT a.id AS account_id, a.code, a.name, a.account_type,
             sum(CASE WHEN a.account_type = 'asset' THEN jl.base_debit - jl.base_credit
                      ELSE jl.base_credit - jl.base_debit END) AS amount
      #{POSTED} AND a.account_type IN ('asset', 'liability', 'equity')
        AND (:d::date IS NULL OR je.entry_date <= :d::date)
      GROUP BY a.id ORDER BY a.code
    SQL
    earnings = rows(<<~SQL, d: as_of).first["v"]
      SELECT COALESCE(sum(jl.base_credit - jl.base_debit), 0) AS v
      #{POSTED} AND a.account_type IN ('revenue', 'expense') AND (:d::date IS NULL OR je.entry_date <= :d::date)
    SQL
    { "rows" => money(result, "amount"), "current_earnings" => Values.fmt4(earnings) }
  end

  def cash_flow(from, to)
    p = { f: from, t: to }
    net_income = rows(<<~SQL, p).first["v"]
      SELECT COALESCE(sum(jl.base_credit - jl.base_debit), 0) AS v
      #{POSTED} AND NOT je.is_closing AND a.account_type IN ('revenue', 'expense') #{RANGE}
    SQL
    result = rows(<<~SQL, p)
      SELECT a.id AS account_id, a.code, a.name, a.cash_flow_activity AS activity,
             sum(jl.base_credit - jl.base_debit) AS amount
      #{POSTED} AND NOT je.is_closing AND NOT a.is_cash AND a.account_type IN ('asset', 'liability', 'equity') #{RANGE}
      GROUP BY a.id ORDER BY a.code
    SQL
    cash = rows(<<~SQL, p).first
      SELECT COALESCE(sum(jl.base_debit - jl.base_credit)
                 FILTER (WHERE :f::date IS NOT NULL AND je.entry_date < :f::date), 0) AS opening,
             COALESCE(sum(jl.base_debit - jl.base_credit)
                 FILTER (WHERE (:f::date IS NULL OR je.entry_date >= :f::date)
                           AND (:t::date IS NULL OR je.entry_date <= :t::date)), 0) AS movement,
             COALESCE(sum(jl.base_debit - jl.base_credit) FILTER (WHERE :t::date IS NULL OR je.entry_date <= :t::date), 0) AS closing
      #{POSTED} AND a.is_cash
    SQL
    { "net_income" => Values.fmt4(net_income), "rows" => money(result, "amount"),
      "net_cash_flow" => Values.fmt4(cash["movement"]), "opening_cash" => Values.fmt4(cash["opening"]),
      "closing_cash" => Values.fmt4(cash["closing"]) }
  end

  AGING_BUCKETS = %w[total_outstanding not_yet_due days_1_30 days_31_60 days_61_90 days_over_90].freeze

  def aging(sales)
    view, party, table = sales ? %w[ar_aging customer_id customers] : %w[ap_aging supplier_id suppliers]
    money(rows(<<~SQL), *AGING_BUCKETS)
      SELECT g.#{party} AS party_id, o.name AS party_name, g.total_outstanding,
             COALESCE(g.not_yet_due, 0) AS not_yet_due, COALESCE(g.days_1_30, 0) AS days_1_30,
             COALESCE(g.days_31_60, 0) AS days_31_60, COALESCE(g.days_61_90, 0) AS days_61_90,
             COALESCE(g.days_over_90, 0) AS days_over_90
      FROM #{view} g JOIN #{table} p ON p.id = g.#{party} JOIN organizations o ON o.id = p.organization_id
      ORDER BY g.#{party}
    SQL
  end

  def inventory_valuation
    money(rows(<<~SQL), "qty_on_hand", "value_on_hand", "avg_unit_cost")
      SELECT v.product_id, p.sku, p.name, v.qty_on_hand, v.value_on_hand, v.avg_unit_cost
      FROM stock_valuation v JOIN products p ON p.id = v.product_id ORDER BY p.sku, p.id
    SQL
  end
end
