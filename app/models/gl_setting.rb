# The single row of ledger settings (id 1).
class GlSetting < ApplicationRecord
  def self.current = find(1)
end
