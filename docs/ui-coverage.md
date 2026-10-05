# UI coverage

**Status:** written 2026-10-05, when the UI was first completed.

This records where each item of the UI checklist in `spec/domain.md` §13 is
met, and how it was checked. `docs/counterpart-metrics.md` in tadmor asks
for a walk-through, item by item, before a counterpart's figures count;
this is the record of it.

**How it was checked.**

- **Test** means `test/ui_test.rb` drives it: Rails integration tests that
  send requests through the full middleware stack with cookies kept, post
  forms with their tokens, and read the pages back. They run with
  `make test`.
- **Browser** means a scripted walk-through in headless Chromium on
  2026-10-05, against a production-mode server on a database full of
  conformance-suite data. It used tadmor's Playwright install from outside
  this repo, so it is not a dependency here and nothing in the repo runs
  it. It made 65 checks, all passing, among them the line editor's fills
  and exact previews (`public/app.js`), the delete confirmations, and
  role-based hiding. It found no console errors and no Content Security
  Policy violations on any page.
- **Smoke** means the page was fetched on that same data and returned 200:
  every list and new-record form, 80 document, payment, order, movement,
  and statement detail screens with their edit and delete pages, 60 ledgers,
  40 journal entries, and the fulfilment forms of six open orders. Key
  screens were also screenshotted and inspected. No test asserts their
  content.

## General

| Item | Where | Checked |
| ---- | ----- | ------- |
| G1 | `/login`; every other UI path redirects there without a session (`Ui::BaseController#require_login`), returning afterwards to the page asked for | Test, Browser (failed login, return to the page asked for) |
| G2 | The signed-in user's name and Sign out, in the header of every page | Test, Browser |
| G3 | The sidebar on every page (`UiHelper::NAV`) | Test (every link opens), Browser |
| G4 | Users hidden from the sidebar and refused with 403; unpost, statement reopen, and year-end close and reopen shown only to administrators; settings read-only. The services refuse them regardless | Test (Users, settings, unpost), Browser (Users link and page, unpost, year-end, settings) |
| G5 | A refusal re-renders the form or detail screen with the server's message next to the action, keeping what was typed | Test (missing name, posting a zero total, a short password, deactivating oneself), Browser (posting without an exchange rate) |
| G6 | Deleting a document, payment, order, stock movement, bank statement, or exchange rate goes through a confirmation page first | Test, Browser (cancel keeps it, confirm deletes) |
| G7 | Amounts exact and grouped, never rounded (`UiHelper#amount`); the currency beside every document amount | Test (`10.0011`), Browser (EUR invoice) |
| G8 | The not-found page for unknown addresses and records | Test, Browser |

## Home

| Item | Where | Checked |
| ---- | ----- | ------- |
| H1 | Receivables and payables outstanding per currency, each with its overdue part | Test |
| H2 | Open sales and purchase orders, draft invoices and bills | Smoke |
| H3 | The ten most overdue invoices, oldest due date first, linking to each, with a link to AR aging | Test |
| H4 | Bills due in the next 14 days, linking to each, with a link to AP aging | Smoke |
| H5 | New invoice, customer payment, bill, supplier payment, sales order, and purchase order buttons | Test |

## Master data

| Item | Where | Checked |
| ---- | ----- | ------- |
| M1 | `/organizations`: list and form | Test |
| M2 | `/customers`, `/suppliers`: lists and forms; the organization is read-only on edit | Test (customer), Smoke (supplier) |
| M3 | `/products`: list and form, with revenue, inventory, and COGS accounts | Smoke, Browser (filling invoice lines from a product) |
| M4 | `/accounts`: list and form; the parent picker never offers the account itself | Test |
| M5 | `/tax-codes`, `/payment-terms`, `/warehouses`: lists and forms | Test (forms open), Smoke |
| M6 | Active status in every list with `is_active`; deactivation through the form; no delete | Test (customer deactivated and shown as Inactive) |
| M7 | `/users`: list, create form with password, edit form, separate password reset; deactivating or demoting oneself refused | Test |
| M8 | `/settings`: base currency and FX account, read-only for non-administrators | Test, Browser |

## Invoices, bills, and credit notes

| Item | Where | Checked |
| ---- | ----- | ------- |
| D1 | `/sales-invoices`, `/purchase-bills`, `/sales-credit-notes`, `/purchase-credit-notes`: number, party, dates, total, balance or unapplied, statuses, newest first | Test, Smoke |
| D2 | The header-and-lines form: lines added and removed; a product fills description, tax code, and on the sales side price and revenue account; a tax code fills the rate; totals previewed exactly as the user types | Browser (every fill, a negative line, add and remove, `10.0011` and `1.2501` previews) |
| D3 | The detail screen: header, every line, totals, statuses, and the journal entry link once posted | Test, Browser |
| D4 | Post, edit, and delete on drafts (no edit when produced from an order); unpost for administrators; apply on a posted credit note with something unapplied | Test, Browser |
| D5 | A credit note's "Applied to" list, linking to each document | Smoke |
| D6 | The PDF button opens `/api/{collection}/{id}/pdf` | Test, Browser (the PDF's structure and text checked) |
| D7 | The email box: optional recipients; shows the addresses used, or the error | Test, Browser (501 when sending is disabled) |

## Payments

| Item | Where | Checked |
| ---- | ----- | ------- |
| P1 | `/customer-payments`, `/supplier-payments`: party, date, method, amount, applied, unapplied, status, newest first | Test |
| P2 | The payment form, with the deposit or payment account | Test |
| P3 | The detail screen with the journal entry link; post, edit, and delete on drafts; apply while something is unapplied; unpost for administrators | Test |
| P4 | The "Applied to" list on the detail screen, linking to each document | Test |

## Orders

| Item | Where | Checked |
| ---- | ----- | ------- |
| O1 | `/sales-orders`, `/purchase-orders`: number, party, date, total, status, and both fulfilment statuses, newest first | Smoke |
| O2 | The header-and-lines form, as D2, for drafts only | Test |
| O3 | The detail screen: statuses, and per line the ordered, invoiced (billed), and shipped (received) quantities and what remains on each axis | Test |
| O4 | Confirm, edit, delete, and cancel on drafts; close and cancel on open orders, cancel only while nothing is fulfilled | Test |
| O5 | Invoice (bill): number, date, and due date, with each outstanding line's remaining quantity filled in and lowerable; goes to the new draft | Test (a partial invoice) |
| O6 | Ship (receive): warehouse and date, only stocked outstanding lines, with links to the movements created | Test |
| O7 | PDF and email, as D6 and D7 | Smoke |

## Inventory

| Item | Where | Checked |
| ---- | ----- | ------- |
| S1 | `/stock-movements`: date, product, warehouse, type, quantity, unit cost, total cost, posted, newest first | Smoke |
| S2 | The movement form, with the quantity entered as a magnitude and signed by the type, an adjustment as typed | Test (an issue of 3 stored as -3) |
| S3 | The detail screen: post (a receipt asks for the account to credit, proposing GRNI), edit unless from an order, delete, unpost for administrators | Test |

## Reports

| Item | Where | Checked |
| ---- | ----- | ------- |
| R1 | `/reports/profit-and-loss`: revenue and expense sections with totals and net income | Test |
| R2 | `/reports/balance-sheet`: assets, liabilities, equity, and current earnings, with the identity stated | Test |
| R3 | `/reports/cash-flow`: operating (from net income), investing, and financing with subtotals; opening cash, net cash flow, closing cash | Test |
| R4 | `/reports/trial-balance`: every account with debit, credit, and balance, and totals; each links to its ledger | Test |
| R5 | `/accounts/{id}/ledger`: date, journal entry link, memo, debit and credit, running balance from the opening balance; currency and base amounts when foreign | Test, Smoke (60 ledgers, with and without a range) |
| R6 | `/journal-entries/{id}`: header and every line, accounts linking to ledgers, base amounts, totals | Test, Browser |
| R7 | `/reports/ar-aging`, `/reports/ap-aging`: the five buckets and total per party, and a total row | Test |
| R8 | `/inventory-valuation`: sku, product, quantity, average unit cost, value, and a total | Test |

Every date bound is optional, and a malformed one shows its error above the
report (Test).

## Accounting

| Item | Where | Checked |
| ---- | ----- | ------- |
| A1 | `/periods`: fiscal years with their periods; forms for each; the new-period form proposes the month after the latest period; one-step close and reopen per period | Test |
| A2 | Year-end close, proposing Retained Earnings and stating what will happen; reopen of the latest closed year; administrators only | Test |
| A3 | `/exchange-rates`: list, create, change, and delete | Test |
| A4 | `/bank-statements`: list and form, offering only cash accounts | Test |
| A5 | The statement detail: lines added by hand and imported from pasted CSV, deleted, auto-matched, matched from candidates of the same amount or from all candidates, unmatched; reconcile, edit, delete; reopen for administrators | Test (a line added and deleted, import and its refusal, auto-match, unmatch, reconcile, reopen offered), Browser |
