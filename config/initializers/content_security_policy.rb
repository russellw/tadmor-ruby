# Same-origin only: every script, style, and image is served by us, so the
# templates use no inline script or style.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.img_src :self, :data
    policy.frame_ancestors :none
    policy.form_action :self
    policy.base_uri :self
  end
end
