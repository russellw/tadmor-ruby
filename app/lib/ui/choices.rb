module Ui
  # Pickers over active records (domain §13: "a picker over active records
  # for each reference"). Each returns a callable, so a form lists the
  # records current when it is shown.
  module Choices
    module_function

    def accounts(**filters)
      -> { Account.where(is_active: true, **filters).order(:code).map { [_1.id, "#{_1.code} #{_1.name}"] } }
    end

    def postable_accounts = accounts(is_postable: true)
    def currencies = -> { Currency.order(:code).map { [_1.code, "#{_1.code} #{_1.name}"] } }
    def countries = -> { Country.order(:code).map { [_1.code, "#{_1.code} #{_1.name}"] } }
    def organizations = -> { Organization.order(:name).pluck(:id, :name) }

    def parties(model, number)
      lambda do
        model.where(is_active: true).includes(:organization).sort_by { _1.organization.name.downcase }.map do |p|
          [p.id, p[number].present? ? "#{p.organization.name} (#{p[number]})" : p.organization.name]
        end
      end
    end

    def customers = parties(Customer, :customer_number)
    def suppliers = parties(Supplier, :supplier_number)
    def tax_codes = -> { TaxCode.where(is_active: true).order(:code).map { [_1.code, "#{_1.code} #{_1.name}"] } }
    def payment_terms = -> { PaymentTerm.order(:due_days, :code).pluck(:code, :name) }

    def products(**filters)
      -> { Product.where(is_active: true, **filters).order(:sku).map { [_1.id, "#{_1.sku} #{_1.name}"] } }
    end

    def warehouses = -> { Warehouse.where(is_active: true).order(:code).map { [_1.id, "#{_1.code} #{_1.name}"] } }
    def fiscal_years = -> { FiscalYear.order(:start_date).pluck(:id, :name) }
    def static(*pairs) = -> { pairs }
  end
end
