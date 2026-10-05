# Errors that carry their HTTP status (spec/api.md §1.4).
#
# The service layer raises these; the JSON API turns them into
# {"error": ...} responses and the UI shows their message next to the action
# that failed. Database errors that escape the service layer's own checks are
# translated by ApiError.from_database according to their SQLSTATE.
class ApiError < StandardError
  def self.status = 500

  def status = self.class.status

  class BadRequest < ApiError
    def self.status = 400
  end

  class Unauthorized < ApiError
    def self.status = 401
  end

  class Forbidden < ApiError
    def self.status = 403
  end

  class NotFound < ApiError
    def self.status = 404
  end

  class Conflict < ApiError
    def self.status = 409
  end

  class Unprocessable < ApiError
    def self.status = 422
  end

  class NotConfigured < ApiError
    def self.status = 501
  end

  # SQLSTATEs that mean the request, not the server, is at fault.
  BY_SQLSTATE = {
    "23505" => Conflict,      # unique_violation
    "23503" => Unprocessable, # foreign_key_violation
    "23514" => Unprocessable, # check_violation
    "23P01" => Unprocessable, # exclusion_violation (overlapping periods)
    "23502" => Unprocessable, # not_null_violation
    "22003" => Unprocessable, # numeric_value_out_of_range
    "22007" => Unprocessable, # invalid_datetime_format
    "22008" => Unprocessable, # datetime_field_overflow
    "22P02" => Unprocessable, # invalid_text_representation
    "P0001" => Unprocessable, # raise_exception from a trigger
  }.freeze

  # The ApiError for a database error, or nil if it is a server fault.
  def self.from_database(error)
    pg = error.cause
    return nil unless pg.is_a?(PG::Error) && pg.result

    state = pg.result.error_field(PG::PG_DIAG_SQLSTATE)
    cls = BY_SQLSTATE[state] or return nil
    cls.new(friendly(state, pg.result) || pg.result.error_field(PG::PG_DIAG_MESSAGE_PRIMARY).to_s.strip)
  end

  # A message naming the offending column, for the common constraint kinds.
  def self.friendly(state, result)
    constraint = result.error_field(PG::PG_DIAG_CONSTRAINT_NAME).to_s
    table = result.error_field(PG::PG_DIAG_TABLE_NAME).to_s
    column = constraint.delete_prefix("#{table}_")
    case state
    when "23503"
      "unknown #{column.delete_suffix('_fkey')}" if column.end_with?("_fkey")
    when "23505"
      column.end_with?("_key") ? "#{column.delete_suffix('_key')} already exists" : "a record with the same key already exists"
    when "23P01"
      "overlaps an existing record"
    end
  end
end
