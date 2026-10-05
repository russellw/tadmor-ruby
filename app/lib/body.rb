# Typed read access to a JSON object from a request.
#
# A value of the wrong JSON type is a 400 (the request cannot be
# interpreted). A string that does not hold a valid decimal or date is a
# 422 (spec/api.md §1.4). Absent and null are the same thing.
class Body
  attr_reader :data

  def self.parse(raw)
    return new({}) if raw.to_s.strip.empty?

    new(JSON.parse(raw))
  rescue JSON::ParserError, EncodingError => e
    raise ApiError::BadRequest, "invalid JSON body: #{e.message.lines.first&.strip}"
  end

  def initialize(data)
    raise ApiError::BadRequest, "request body must be a JSON object" unless data.is_a?(Hash)

    @data = data
  end

  def has?(name) = !@data[name].nil?

  def raw(name) = @data[name]

  def str(name)
    v = @data[name]
    raise ApiError::BadRequest, "#{name} must be a string" unless v.nil? || v.is_a?(String)

    v
  end

  # An optional text field: absent, null, and "" all mean null.
  def text(name) = str(name).presence

  def required_str(name)
    v = str(name)
    raise ApiError::BadRequest, "#{name} is required" if v.nil? || v.empty?

    v
  end

  def int(name)
    v = @data[name]
    raise ApiError::BadRequest, "#{name} must be an integer" unless v.nil? || v.is_a?(Integer)

    v
  end

  def required_id(name)
    v = int(name)
    raise ApiError::BadRequest, "#{name} is required" if v.nil? || v <= 0

    v
  end

  def bool(name)
    v = @data[name]
    return false if v.nil?
    raise ApiError::BadRequest, "#{name} must be a boolean" unless v == true || v == false

    v
  end

  def decimal(name, kind = Values::MONEY, default: nil)
    v = str(name)
    return default if v.nil? || v.empty?

    Values.parse_decimal(v, kind, name)
  end

  def date(name)
    v = str(name)
    return nil if v.nil? || v.empty?

    Values.parse_date(v, name)
  end

  def list(name)
    v = @data[name]
    return [] if v.nil?
    raise ApiError::BadRequest, "#{name} must be an array" unless v.is_a?(Array)

    v.map { |item| Body.new(item) }
  end
end
