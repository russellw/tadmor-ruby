module Api
  # Year-end close and reopen, administrators only (spec/api.md §5.7).
  class FiscalYearsController < BaseController
    admin_only

    def close = ok(YearEnd.close(id, body.required_id("retained_earnings_account_id")))

    def reopen = ok(reversal_entry_id: YearEnd.reopen(id))
  end
end
