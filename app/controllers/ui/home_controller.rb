module Ui
  # The home page (domain §13.2, H1–H5).
  class HomeController < BaseController
    def show
      today = Values.today
      page "ui/home", title: "Home", today:,
                      receivables: outstanding(SalesInvoiceBalance, today),
                      payables: outstanding(PurchaseBillBalance, today),
                      counts: { sales_orders: SalesOrder.where(status: "open").count,
                                purchase_orders: PurchaseOrder.where(status: "open").count,
                                draft_invoices: SalesInvoice.where(status: "draft").count,
                                draft_bills: PurchaseBill.where(status: "draft").count },
                      overdue: overdue_invoices(today), due_soon: bills_due_soon(today)
    end

    private

    # H1: posted documents with a positive balance, per currency, with the overdue part.
    def outstanding(view, today)
      Reports.rows(<<~SQL, today)
        SELECT currency_code, sum(balance) AS total, count(*) AS n,
               COALESCE(sum(balance) FILTER (WHERE due_date < ?), 0) AS overdue
        FROM #{view.table_name} WHERE status = 'posted' AND balance > 0
        GROUP BY currency_code ORDER BY currency_code
      SQL
    end

    # H3: the most overdue invoices, oldest due date first.
    def overdue_invoices(today)
      Reports.rows(<<~SQL, today)
        SELECT b.invoice_id AS id, i.invoice_number AS number, o.name AS party, b.due_date, b.currency_code, b.balance
        FROM sales_invoice_balances b JOIN sales_invoices i ON i.id = b.invoice_id
        JOIN customers c ON c.id = i.customer_id JOIN organizations o ON o.id = c.organization_id
        WHERE b.status = 'posted' AND b.balance > 0 AND b.due_date < ?
        ORDER BY b.due_date, b.invoice_id LIMIT 10
      SQL
    end

    # H4: bills due within the next 14 days.
    def bills_due_soon(today)
      Reports.rows(<<~SQL, today, today + 14)
        SELECT b.bill_id AS id, p.bill_number AS number, o.name AS party, b.due_date, b.currency_code, b.balance
        FROM purchase_bill_balances b JOIN purchase_bills p ON p.id = b.bill_id
        JOIN suppliers s ON s.id = p.supplier_id JOIN organizations o ON o.id = s.organization_id
        WHERE b.status = 'posted' AND b.balance > 0 AND b.due_date BETWEEN ? AND ?
        ORDER BY b.due_date, b.bill_id LIMIT 10
      SQL
    end
  end
end
