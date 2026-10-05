require "csv"

# Bank statements and reconciliation (spec/api.md §5.13, domain §8).
#
# A statement belongs to one postable, active cash account. Each of its
# lines matches at most one posted journal line on that account with the
# same signed transaction-currency amount, and a journal line backs at most
# one statement line anywhere. The schema enforces the account and match
# rules and freezes reconciled statements; the checks here give the
# refusals their statuses.
module Banking
  AMOUNT = /\A-?(\d+(\.\d*)?|\.\d+)\z/

  module_function

  def scope
    BankStatement.includes(:account).select(
      "bank_statements.*",
      "(SELECT count(*) FROM bank_statement_lines l WHERE l.statement_id = bank_statements.id) AS n_lines",
      "(SELECT count(*) FROM bank_statement_lines l WHERE l.statement_id = bank_statements.id " \
      "AND l.journal_line_id IS NOT NULL) AS n_matched",
      "(SELECT COALESCE(sum(amount), 0) FROM bank_statement_lines l WHERE l.statement_id = bank_statements.id) AS lines_total",
    )
  end

  def json(s)
    { "id" => s.id, "account_id" => s.account_id, "account_code" => s.account.code, "account_name" => s.account.name,
      "statement_date" => Values.fmt_date(s.statement_date), "opening_balance" => Values.fmt4(s.opening_balance),
      "closing_balance" => Values.fmt4(s.closing_balance), "reference" => s.reference, "status" => s.status,
      "line_count" => s.n_lines, "matched_count" => s.n_matched, "lines_total" => Values.fmt4(s.lines_total),
      "difference" => Values.fmt4(s.opening_balance + s.lines_total - s.closing_balance) }
  end

  def list = scope.order(statement_date: :desc, id: :desc).map { json(_1) }

  def get(id) = scope.find_by(id:) || raise(ApiError::NotFound, "bank statement not found")

  def required(b)
    b.required_id("account_id")
    b.required_str("statement_date")
    b.required_str("opening_balance")
    b.required_str("closing_balance")
  end

  def fields(b)
    account = b.int("account_id")
    unless Account.exists?(id: account, is_postable: true, is_active: true, is_cash: true)
      raise ApiError::Unprocessable, "the account must be a postable, active cash account"
    end

    { account_id: account, statement_date: Values.parse_date(b.str("statement_date"), "statement_date"),
      opening_balance: b.decimal("opening_balance"), closing_balance: b.decimal("closing_balance"),
      reference: b.text("reference") }
  end

  def create(b, user = nil)
    required(b)
    BankStatement.create!(fields(b).merge(created_by: user&.id)).id
  end

  def lock_open(id)
    s = BankStatement.lock.find_by(id:) || raise(ApiError::NotFound, "bank statement not found")
    raise ApiError::Conflict, "the bank statement is reconciled" if s.status != "open"

    s
  end

  def update(id, b)
    required(b)
    s = lock_open(id)
    f = fields(b)
    if f[:account_id] != s.account_id && s.lines.where.not(journal_line_id: nil).exists?
      raise ApiError::Unprocessable, "unmatch the statement's lines before changing its account"
    end

    BankStatement.where(id:).update_all(f)
  end

  def delete(id)
    lock_open(id)
    BankStatementLine.where(statement_id: id).delete_all
    BankStatement.where(id:).delete_all
  end

  # -- Lines -------------------------------------------------------------------------

  def line_json(l)
    je = l.journal_line&.journal_entry
    { "id" => l.id, "line_no" => l.line_no, "txn_date" => Values.fmt_date(l.txn_date), "description" => l.description,
      "reference" => l.reference, "amount" => Values.fmt4(l.amount), "journal_line_id" => l.journal_line_id,
      "journal_entry_id" => je&.id, "entry_date" => Values.fmt_date(je&.entry_date), "entry_memo" => je&.memo }
  end

  def lines(id)
    get(id)
    BankStatementLine.where(statement_id: id).includes(journal_line: :journal_entry).order(:line_no).map { line_json(_1) }
  end

  def append(statement_id, txn_date, description, reference, amount)
    line_no = BankStatementLine.where(statement_id:).maximum(:line_no).to_i + 1
    BankStatementLine.create!(statement_id:, line_no:, txn_date:, description:, reference:, amount:).id
  end

  def add_line(id, b)
    b.required_str("txn_date")
    b.required_str("description")
    b.required_str("amount")
    lock_open(id)
    amount = b.decimal("amount")
    raise ApiError::Unprocessable, "amount must not be zero" if amount.zero?

    append(id, Values.parse_date(b.str("txn_date"), "txn_date"), b.str("description"), b.text("reference"), amount)
  end

  # Statement lines from `date,description,amount[,reference]` CSV (domain §8.2).
  def parse_csv(text)
    records = begin
      CSV.parse(text, strip: true, liberal_parsing: false)
    rescue CSV::MalformedCSVError => e
      raise ApiError::Unprocessable, "invalid CSV: #{e.message}"
    end
    rows = []
    records.each.with_index(1) do |rec, i|
      next if rec.empty? || (rec.size == 1 && rec[0].to_s.strip.empty?)
      unless [3, 4].include?(rec.size)
        raise ApiError::Unprocessable, "record #{i} has #{rec.size} fields; want date,description,amount[,reference]"
      end

      rec = rec.map { _1.to_s.strip }
      date = begin
        Values.parse_date(rec[0])
      rescue ApiError::Unprocessable
        next if i == 1 # a header row

        raise ApiError::Unprocessable, "record #{i}: #{rec[0].inspect} is not a YYYY-MM-DD date"
      end
      raise ApiError::Unprocessable, "record #{i}: the description is empty" if rec[1].empty?
      raise ApiError::Unprocessable, "record #{i}: #{rec[2].inspect} is not a decimal amount" unless AMOUNT.match?(rec[2])

      amount = Values.parse_decimal(rec[2], Values::MONEY, "record #{i} amount")
      raise ApiError::Unprocessable, "record #{i}: the amount must not be zero" if amount.zero?

      rows << [date, rec[1], rec.size == 4 ? rec[3].presence : nil, amount]
    end
    raise ApiError::Unprocessable, "the CSV has no data rows" if rows.empty?

    rows
  end

  def import_csv(id, b)
    text = b.str("csv")
    raise ApiError::BadRequest, "csv is required" if text.blank?

    lock_open(id)
    rows = parse_csv(text)
    rows.each { |date, description, reference, amount| append(id, date, description, reference, amount) }
    rows.size
  end

  def lock_line(line_id)
    line = BankStatementLine.lock.includes(:statement).find_by(id: line_id) ||
           raise(ApiError::NotFound, "bank statement line not found")
    raise ApiError::Conflict, "the bank statement is reconciled" if line.statement.status != "open"

    line
  end

  def delete_line(line_id)
    lock_line(line_id)
    BankStatementLine.where(id: line_id).delete_all
  end

  def match(line_id, b)
    journal_line_id = b.int("journal_line_id")
    raise ApiError::BadRequest, "journal_line_id is required" if journal_line_id.nil? || journal_line_id <= 0

    line = lock_line(line_id)
    raise ApiError::Conflict, "the statement line is already matched" if line.journal_line_id

    jl = JournalLine.includes(:journal_entry).find_by(id: journal_line_id)
    if jl.nil? || jl.journal_entry.status != "posted"
      raise ApiError::Unprocessable, "journal_line_id must name a line of a posted journal entry"
    end
    raise ApiError::Unprocessable, "the journal line is on a different account" if jl.account_id != line.statement.account_id
    if jl.debit - jl.credit != line.amount
      raise ApiError::Unprocessable, "the journal line's amount differs from the statement line's"
    end
    if BankStatementLine.exists?(journal_line_id:)
      raise ApiError::Conflict, "the journal line already backs another statement line"
    end

    BankStatementLine.where(id: line_id).update_all(journal_line_id:)
  end

  def unmatch(line_id)
    lock_line(line_id)
    BankStatementLine.where(id: line_id).update_all(journal_line_id: nil)
  end

  CANDIDATES = <<~SQL.freeze
    SELECT jl.id AS journal_line_id, je.id AS journal_entry_id, je.entry_date, je.reference,
           COALESCE(jl.memo, je.memo) AS memo, jl.debit - jl.credit AS amount
    FROM journal_lines jl
    JOIN journal_entries je ON je.id = jl.journal_entry_id
    WHERE je.status = 'posted' AND jl.account_id = ?
      AND NOT EXISTS (SELECT 1 FROM bank_statement_lines b WHERE b.journal_line_id = jl.id)
  SQL

  def candidates(id)
    s = get(id)
    Reports.rows("#{CANDIDATES} ORDER BY je.entry_date, je.id, jl.line_no", s.account_id).each do |r|
      r["entry_date"] = Values.fmt_date(r["entry_date"])
      r["amount"] = Values.fmt4(r["amount"])
    end
  end

  def auto_match(id)
    s = lock_open(id)
    matched = 0
    BankStatementLine.where(statement_id: id, journal_line_id: nil).order(:line_no).each do |line|
      row = Reports.rows("#{CANDIDATES} AND jl.debit - jl.credit = ? ORDER BY abs(je.entry_date - ?::date), jl.id LIMIT 1",
                         s.account_id, line.amount, line.txn_date).first
      next unless row

      BankStatementLine.where(id: line.id).update_all(journal_line_id: row["journal_line_id"])
      matched += 1
    end
    matched
  end

  def reconcile(id)
    s = lock_open(id)
    lines = BankStatementLine.where(statement_id: id)
    raise ApiError::Unprocessable, "every line must be matched before reconciling" if lines.where(journal_line_id: nil).exists?
    if s.opening_balance + lines.sum(:amount) != s.closing_balance
      raise ApiError::Unprocessable, "opening balance plus the lines does not equal the closing balance"
    end

    BankStatement.where(id:).update_all(status: "reconciled", reconciled_at: Time.now.utc)
  end

  def reopen(id)
    s = BankStatement.lock.find_by(id:) || raise(ApiError::NotFound, "bank statement not found")
    raise ApiError::Conflict, "the bank statement is not reconciled" if s.status != "reconciled"

    BankStatement.where(id:).update_all(status: "open", reconciled_at: nil)
  end
end
