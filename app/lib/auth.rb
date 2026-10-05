require "openssl"

# Login sessions and passwords (spec/api.md §3, domain §12).
#
# Sessions live in the shared sessions table, keyed by the SHA-256 of a
# random bearer token; the raw token exists only in the client's cookie. A
# session lasts a fixed 30 days from login. The user's active and admin flags
# are re-read on every request, so deactivation and demotion take effect
# immediately. Passwords are PBKDF2-HMAC-SHA256 at 600,000 iterations, as in
# tadmor, through Ruby's OpenSSL binding.
module Auth
  COOKIE = "tadmor_session".freeze
  TTL = 30.days
  MIN_PASSWORD = 8
  ITERATIONS = 600_000

  # The signed-in user, as the API returns it.
  CurrentUser = Data.define(:id, :email, :full_name, :is_admin) do
    def as_json(*) = { "id" => id, "email" => email, "full_name" => full_name, "is_admin" => is_admin }
  end

  module_function

  def hash_password(password, salt: SecureRandom.hex(16), iterations: ITERATIONS)
    key = OpenSSL::KDF.pbkdf2_hmac(password, salt:, iterations:, length: 32, hash: "sha256")
    "pbkdf2_sha256$#{iterations}$#{salt}$#{[key].pack('m0')}"
  end

  def password_matches?(password, stored)
    scheme, iterations, salt, _ = stored.to_s.split("$", 4)
    return false unless scheme == "pbkdf2_sha256" && iterations.to_i.positive?

    OpenSSL.secure_compare(hash_password(password, salt:, iterations: iterations.to_i), stored)
  end

  # The active user with these credentials, or nil. Unknown emails still run
  # a full hash, so all three failures (unknown, wrong password, deactivated)
  # take the same time.
  def authenticate(email, password)
    user = User.find_by(email: email.strip, is_active: true)
    if user.nil?
      hash_password(password)
      return nil
    end
    password_matches?(password, user.password_hash) ? user : nil
  end

  def token_hash(token) = Digest::SHA256.digest(token)

  def start_session(user)
    token = SecureRandom.urlsafe_base64(32)
    now = Time.now.utc
    LoginSession.where(expires_at: ...now).delete_all
    LoginSession.insert!({ token_hash: token_hash(token), user_id: user.id, expires_at: now + TTL })
    token
  end

  def end_session(token)
    LoginSession.where(token_hash: token_hash(token)).delete_all if token.present?
  end

  def session_user(token)
    return nil if token.blank?

    u = LoginSession.where(token_hash: token_hash(token), expires_at: Time.now.utc..).joins(:user)
                    .where(users: { is_active: true })
                    .pick("users.id", "users.email", "users.full_name", "users.is_admin")
    u && CurrentUser.new(*u)
  end

  # The session cookie, for a controller's cookie jar.
  def cookie(request, token)
    { value: token, expires: TTL.from_now, httponly: true, same_site: :lax, secure: request.ssl?, path: "/" }
  end
end
