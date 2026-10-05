module Api
  # The journal and the reports (spec/api.md §5.14).
  class ReportsController < BaseController
    def journal_entry = ok(Reports.journal_entry(id))

    def ledger = ok(Reports.ledger(id, date_param("from"), date_param("to")))

    def trial_balance = ok(Reports.trial_balance)
    def profit_and_loss = ok(Reports.profit_and_loss(date_param("from"), date_param("to")))
    def balance_sheet = ok(Reports.balance_sheet(date_param("as_of")))
    def cash_flow = ok(Reports.cash_flow(date_param("from"), date_param("to")))
    def ar_aging = ok(Reports.aging(true))
    def ap_aging = ok(Reports.aging(false))
    def inventory_valuation = ok(Reports.inventory_valuation)
  end
end
