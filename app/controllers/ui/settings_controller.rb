module Ui
  # Ledger settings, read-only for non-administrators (domain §13.3 M8).
  class SettingsController < BaseController
    def show
      fields = [
        Field.of("base_currency", "Base currency", "select", Choices.currencies, required: true,
                 help: "Cannot change once any journal entry exists."),
        Field.of("fx_gain_loss_account_id", "FX gain/loss account", "ref", Choices.postable_accounts,
                 help: "Realized exchange differences on settlement post here."),
      ]
      crud_form(title: "Settings", fields:, initial: Master.settings_json(GlSetting.current), back: "/",
                done: ->(_) { "/settings?saved=1" }, readonly: !current_user.is_admin,
                notice: params[:saved] ? "Settings saved." : nil) { Master.update_settings(_1) }
    end
  end
end
