# A row of the shared sessions table, keyed by the SHA-256 of the bearer token.
class LoginSession < ApplicationRecord
  self.table_name = "sessions"
  self.primary_key = "token_hash"
  belongs_to :user
end
