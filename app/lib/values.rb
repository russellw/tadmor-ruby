require "bigdecimal"

# Exact decimal and date values (spec/api.md §1.2).
#
# Decimals arrive as strings and are rounded half away from zero to their
# stored scale before anything checks or uses them. BigDecimal holds them
# exactly, so nothing passes through binary floating point; products of two
# stored values are exact before they are rounded.
module Values
  # [scale, magnitude limit] per kind of decimal.
  MONEY = [4, BigDecimal("1e15")].freeze
  RATE = [4, BigDecimal(1000)].freeze # a tax rate in percent
  FX = [8, BigDecimal("1e11")].freeze # an exchange rate

  DECIMAL = /\A[+-]?(\d+(\.\d*)?|\.\d+)\z/
  DATE = /\A\d{4}-\d{2}-\d{2}\z/
  ZERO = BigDecimal(0)
  PERCENT = BigDecimal("0.01")

  module_function

  def round4(d) = d.round(4, BigDecimal::ROUND_HALF_UP)

  # A plain decimal string, rounded to the kind's scale.
  def parse_decimal(text, kind = MONEY, name = "value")
    text = text.strip
    raise ApiError::Unprocessable, "#{name} must be a decimal number" unless DECIMAL.match?(text)

    scale, limit = kind
    d = BigDecimal(text.sub(/\A\+/, "").sub(/\A(-?)\./, '\10.').sub(/\.\z/, "")).round(scale, BigDecimal::ROUND_HALF_UP)
    raise ApiError::Unprocessable, "#{name} is out of range" if d.abs >= limit

    d
  end

  # Refuse a computed amount at or beyond the money limit.
  def check_magnitude(d, name = "amount")
    raise ApiError::Unprocessable, "#{name} is out of range" if d.abs >= MONEY[1]

    d
  end

  def parse_date(text, name = "date", error: ApiError::Unprocessable)
    raise error, "#{name} must be a YYYY-MM-DD date" unless DATE.match?(text)

    Date.strptime(text, "%Y-%m-%d")
  rescue Date::Error
    raise error, "#{name} must be a valid YYYY-MM-DD date"
  end

  # Money and quantities: scale 4, e.g. "9.9900".
  def fmt4(d)
    return nil if d.nil?

    whole, frac = plain(round4(BigDecimal(d.to_s)))
    "#{whole}.#{frac.ljust(4, '0')}"
  end

  # Exchange rates: trailing zeros trimmed, e.g. "1.125".
  def fmt_rate(d)
    return nil if d.nil?

    whole, frac = plain(BigDecimal(d.to_s))
    frac = frac.sub(/0+\z/, "")
    frac.empty? ? whole : "#{whole}.#{frac}"
  end

  # A decimal as [signed whole part, fraction digits], never in exponent form.
  def plain(d)
    whole, frac = d.to_s("F").split(".")
    whole = "0" if whole == "-0" && frac.to_s.delete("0").empty?
    [whole, frac.to_s == "0" ? "" : frac.to_s]
  end

  def fmt_date(d) = d&.iso8601

  # Today's date in UTC, whatever the server's timezone (spec/api.md §1.2).
  def today = Time.now.utc.to_date

  # A path id or similar: a positive integer, else 400.
  def positive_int(text, name = "id")
    text = text.to_s
    raise ApiError::BadRequest, "invalid #{name}" unless text.match?(/\A\d{1,9}\z/) && text.to_i.positive?

    text.to_i
  end
end
