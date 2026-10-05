require "net/smtp"

# Sends one message with a PDF attached, over SMTP (net-smtp). The message is
# a plain multipart/mixed MIME document built here: that is all tadmor
# sends, and it does not need Action Mailer and the mail gem (docs/stack.md).
#
# Configured by SMTP_ADDR (host:port), SMTP_USER, SMTP_PASS, and MAIL_FROM.
# Port 465 uses implicit TLS; any other port upgrades with STARTTLS.
module Mailer
  module_function

  def deliver(to:, subject:, body:, attachment:)
    x = Rails.configuration.x
    host, port = x.smtp_addr.split(":", 2)
    port = (port.presence || 587).to_i
    from = x.mail_from.presence || x.smtp_user
    message = compose(from:, to:, subject:, body:, attachment:)

    smtp = Net::SMTP.new(host, port)
    port == 465 ? smtp.enable_tls : smtp.enable_starttls
    auth = x.smtp_user.present? ? [x.smtp_user, x.smtp_pass, :plain] : []
    smtp.start("localhost", *auth) { _1.send_message(message, from, *to) }
  end

  def compose(from:, to:, subject:, body:, attachment:)
    name, data = attachment
    boundary = "tadmor-#{SecureRandom.hex(12)}"
    <<~MIME.gsub("\n", "\r\n")
      From: #{from}
      To: #{to.join(', ')}
      Subject: #{encode_header(subject)}
      Date: #{Time.now.utc.rfc2822}
      Message-ID: <#{SecureRandom.uuid}@#{from.split('@', 2).last.presence || 'localhost'}>
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="#{boundary}"

      --#{boundary}
      Content-Type: text/plain; charset=utf-8
      Content-Transfer-Encoding: base64

      #{[body].pack('m').chomp}
      --#{boundary}
      Content-Type: application/pdf; name="#{name}"
      Content-Disposition: attachment; filename="#{name}"
      Content-Transfer-Encoding: base64

      #{[data].pack('m').chomp}
      --#{boundary}--
    MIME
  end

  # One header line, RFC 2047-encoded when it is not plain ASCII.
  def encode_header(text)
    text = text.tr("\r\n", "  ")
    text.ascii_only? ? text : "=?UTF-8?B?#{[text].pack('m0')}?="
  end
end
