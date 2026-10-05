# Payments have a column named "method", whose generated reader would shadow
# Object#method. Calling method with a name still reaches Object's.
module PaymentMethodColumn
  extend ActiveSupport::Concern

  def method(name = nil)
    name.nil? ? self[:method] : Object.instance_method(:method).bind_call(self, name)
  end
end
