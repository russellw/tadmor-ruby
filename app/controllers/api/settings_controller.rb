module Api
  # Ledger settings and exchange rates (spec/api.md §5.8).
  class SettingsController < BaseController
    admin_only only: :update

    def show = ok(Master.settings_json(GlSetting.current))

    def update
      Master.update_settings(body)
      no_content
    end

    def rates = ok(Master.list_exchange_rates)
    def create_rate = created(Master.create_exchange_rate(body))

    def update_rate
      Master.update_exchange_rate(path_param(:currency), path_param(:date), body)
      no_content
    end

    def delete_rate
      Master.delete_exchange_rate(path_param(:currency), path_param(:date))
      no_content
    end
  end
end
