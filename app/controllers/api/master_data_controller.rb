module Api
  # The list/get/create/update quartet of each master-data collection
  # (spec/api.md §5.2–5.7). The route names the collection; tax codes and
  # payment terms are keyed by code, the rest by id.
  class MasterDataController < BaseController
    # collection => [service, list, get, json, create, update, keyed by code]
    COLLECTIONS = {
      "organizations" => [Master, :list_organizations, :get_organization, :organization_json, :create_organization, :update_organization],
      "customers" => [Master, :list_customers, :get_customer, :customer_json, :create_customer, :update_customer],
      "suppliers" => [Master, :list_suppliers, :get_supplier, :supplier_json, :create_supplier, :update_supplier],
      "products" => [Master, :list_products, :get_product, :product_json, :create_product, :update_product],
      "accounts" => [Master, :list_accounts, :get_account, :account_json, :create_account, :update_account],
      "warehouses" => [Master, :list_warehouses, :get_warehouse, :warehouse_json, :create_warehouse, :update_warehouse],
      "tax-codes" => [Master, :list_tax_codes, :get_tax_code, :tax_code_json, :create_tax_code, :update_tax_code, true],
      "payment-terms" => [Master, :list_payment_terms, :get_payment_term, :payment_term_json, :create_payment_term,
                          :update_payment_term, true],
      "fiscal-years" => [Calendar, :list_fiscal_years, :get_fiscal_year, :fiscal_year_json, :create_fiscal_year,
                         :update_fiscal_year],
      "accounting-periods" => [Calendar, :list_periods, :get_period, :period_json, :create_period, :update_period],
    }.freeze

    def index = ok(service.public_send(spec[1]))
    def show = ok(service.public_send(spec[3], service.public_send(spec[2], key)))

    def create
      new = service.public_send(spec[4], body)
      created(by_code? ? { code: new } : { id: new })
    end

    def update
      k = key
      service.public_send(spec[5], k, body)
      no_content
    end

    private

    def spec = COLLECTIONS.fetch(path_param(:collection))
    def service = spec[0]
    def by_code? = spec[6] == true
    def key = by_code? ? path_param(:id) : id
  end
end
