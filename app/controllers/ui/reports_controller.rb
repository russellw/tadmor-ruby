module Ui
  # Reports (domain §13.8, R1–R8). Every date bound is optional.
  class ReportsController < BaseController
    ZERO = Values::ZERO
    FROM_TO = [%w[from From], %w[to To]].freeze
    AS_OF = [["as_of", "As of"]].freeze

    def profit_and_loss
      d, error = dates("from", "to")
      rows = Reports.profit_and_loss(d["from"], d["to"])
      revenue, expense = %w[revenue expense].map { |t| rows.select { _1["account_type"] == t } }
      page "ui/report_pnl", title: "Profit and loss", error:, filters: FROM_TO, revenue:, expense:,
                            total_revenue: total(revenue), total_expense: total(expense),
                            net_income: total(revenue) - total(expense)
    end

    def balance_sheet
      d, error = dates("as_of")
      bs = Reports.balance_sheet(d["as_of"])
      sections = %w[asset liability equity].to_h { |t| [t, bs["rows"].select { _1["account_type"] == t }] }
      totals = sections.transform_values { total(_1) }
      earnings = BigDecimal(bs["current_earnings"])
      page "ui/report_bs", title: "Balance sheet", error:, filters: AS_OF, sections:, totals:, earnings:,
                           liabilities_and_equity: totals["liability"] + totals["equity"] + earnings
    end

    def cash_flow
      d, error = dates("from", "to")
      cf = Reports.cash_flow(d["from"], d["to"])
      sections = %w[operating investing financing].map do |activity|
        rows = cf["rows"].select { _1["activity"] == activity }
        { name: activity, rows:, subtotal: total(rows) + (activity == "operating" ? BigDecimal(cf["net_income"]) : ZERO) }
      end
      page "ui/report_cf", title: "Cash flow", error:, filters: FROM_TO, cf:, sections:
    end

    def trial_balance
      rows = Reports.trial_balance
      page "ui/report_tb", title: "Trial balance", rows:, total_debit: total(rows, "total_debit"),
                           total_credit: total(rows, "total_credit"), total_balance: total(rows, "balance")
    end

    def ledger
      account = Master.get_account(id)
      d, error = dates("from", "to")
      rows = Reports.ledger(account.id, d["from"], d["to"])
      # The balance carried in from before the range.
      before = d["from"] ? Reports.ledger(account.id, nil, d["from"] - 1) : []
      opening = running = total(before, "base_debit") - total(before, "base_credit")
      rows.each do |r|
        running += BigDecimal(r["base_debit"]) - BigDecimal(r["base_credit"])
        r["running"] = running
      end
      base = Posting.base_currency
      page "ui/report_ledger", title: "Ledger: #{account.code} #{account.name}", error:, filters: FROM_TO, rows:,
                               opening:, closing: running, base:, foreign: rows.any? { _1["currency_code"] != base }
    end

    def journal_entry
      e = Reports.journal_entry(id)
      totals = %w[debit credit base_debit base_credit].to_h { [_1, total(e["lines"], _1)] }
      page "ui/journal_entry", title: "Journal entry #{e['id']}", e:, totals:
    end

    def ar_aging = aging(true)
    def ap_aging = aging(false)

    def inventory_valuation
      rows = Reports.inventory_valuation
      page "ui/report_valuation", title: "Inventory valuation", rows:, total: total(rows, "value_on_hand")
    end

    private

    # Optional YYYY-MM-DD query parameters, and a message if one is malformed.
    def dates(*names)
      error = nil
      values = names.to_h do |n|
        v = params[n].to_s.strip
        [n, v.empty? ? nil : Values.parse_date(v, n)]
      rescue ApiError => e
        error = e.message
        [n, nil]
      end
      [values, error]
    end

    def total(rows, key = "amount") = rows.sum(ZERO) { BigDecimal(_1[key]) }

    def aging(sales)
      rows = Reports.aging(sales)
      page "ui/report_aging", title: sales ? "AR aging" : "AP aging", rows:, sales:,
                              totals: Reports::AGING_BUCKETS.to_h { [_1, total(rows, _1)] }
    end
  end
end
