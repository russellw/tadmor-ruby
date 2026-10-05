module UiHelper
  NAV = [
    ["Overview", [["Home", "/"]]],
    ["Sales", [["Invoices", "/sales-invoices"], ["Credit notes", "/sales-credit-notes"],
               ["Customer payments", "/customer-payments"], ["Sales orders", "/sales-orders"]]],
    ["Purchases", [["Bills", "/purchase-bills"], ["Supplier credits", "/purchase-credit-notes"],
                   ["Supplier payments", "/supplier-payments"], ["Purchase orders", "/purchase-orders"]]],
    ["Inventory", [["Stock movements", "/stock-movements"], ["Inventory valuation", "/inventory-valuation"]]],
    ["Accounting", [["Bank statements", "/bank-statements"], ["Exchange rates", "/exchange-rates"],
                    ["Periods and year-end", "/periods"]]],
    ["Reports", [["Profit and loss", "/reports/profit-and-loss"], ["Balance sheet", "/reports/balance-sheet"],
                 ["Cash flow", "/reports/cash-flow"], ["Trial balance", "/reports/trial-balance"],
                 ["AR aging", "/reports/ar-aging"], ["AP aging", "/reports/ap-aging"]]],
    ["Master data", [["Organizations", "/organizations"], ["Customers", "/customers"], ["Suppliers", "/suppliers"],
                     ["Products", "/products"], ["Chart of accounts", "/accounts"], ["Tax codes", "/tax-codes"],
                     ["Payment terms", "/payment-terms"], ["Warehouses", "/warehouses"]]],
    ["Administration", [["Users", "/users"], ["Settings", "/settings"]]],
  ].freeze
  ADMIN_ONLY = ["/users"].freeze

  # The navigation for the signed-in user (G3, G4): [[group, [[text, url, active]]]].
  def nav_groups
    path = request.path
    NAV.map do |title, links|
      shown = links.reject { |_, url| ADMIN_ONLY.include?(url) && !current_user.is_admin }
      [title, shown.map { |text, url| [text, url, url == "/" ? path == "/" : path.start_with?(url)] }]
    end
  end

  # An exact decimal, grouped, with at least two places: "1,234.50", "10.0011" (G7).
  def amount(v)
    return "" if v.blank?

    Printing.amount(v)
  end

  # A quantity or rate without trailing zeros: "1.5", "3".
  def qty(v) = v.blank? ? "" : Printing.qty(v)

  def negative?(v) = v.present? && BigDecimal(v.to_s).negative?

  # A status or code word made readable: "transfer_in" -> "Transfer in".
  def label(v) = v.blank? ? "" : v.to_s.tr("_", " ").capitalize

  def pill(status) = tag.span(label(status), class: "pill s-#{status}")

  def dash(v) = v.presence || "—"

  def money_span(v) = tag.span(amount(v), class: ("neg" if negative?(v)))

  def form_token_field = hidden_field_tag(:form_token, form_token, id: nil)

  # A one-button form that POSTs to an action.
  def action_button(text, url, css = nil)
    form_tag(url, method: :post, enforce_utf8: false, authenticity_token: false, class: "inline") do
      form_token_field + button_tag(text, class: css, name: nil)
    end
  end

  # A list cell by its column's kind.
  def cell(column, v)
    case column.kind
    when "amount" then money_span(v)
    when "qty" then qty(v)
    when "bool" then v ? "Yes" : tag.span("No", class: "muted")
    when "active" then v ? tag.span("Active", class: "pill ok") : tag.span("Inactive", class: "pill off")
    when "label" then dash(label(v))
    when "status" then pill(v)
    else v.blank? ? tag.span("—", class: "muted") : v.to_s
    end
  end

  def options(choices, selected, blank: nil)
    opts = choices.map { |v, t| [t, v.to_s] }
    opts.unshift([blank, ""]) if blank
    options_for_select(opts, selected.to_s)
  end
end
