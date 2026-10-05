# User administration (spec/api.md §5.1, domain §12).
module Users
  module_function

  def json(u)
    { "id" => u.id, "email" => u.email, "full_name" => u.full_name, "is_active" => u.is_active, "is_admin" => u.is_admin }
  end

  def list = User.order(:email, :id).map { json(_1) }

  def get(id) = User.find_by(id:) || raise(ApiError::NotFound, "user not found")

  def check_email(email)
    email = email.strip
    raise ApiError::Unprocessable, "email must contain @" unless email.include?("@")

    email
  end

  def check_password(password)
    return if password.length >= Auth::MIN_PASSWORD

    raise ApiError::Unprocessable, "password must be at least #{Auth::MIN_PASSWORD} characters"
  end

  def create(b)
    email = b.required_str("email")
    full_name = b.required_str("full_name")
    password = b.required_str("password")
    email = check_email(email)
    check_password(password)
    User.create!(email:, full_name:, password_hash: Auth.hash_password(password), is_admin: b.bool("is_admin")).id
  end

  def update(caller, id, b)
    email = b.required_str("email")
    full_name = b.required_str("full_name")
    is_active, is_admin = b.bool("is_active"), b.bool("is_admin")
    u = get(id)
    email = check_email(email)
    raise ApiError::Unprocessable, "you cannot deactivate yourself" if u.id == caller.id && !is_active
    raise ApiError::Unprocessable, "you cannot remove your own administrator role" if u.id == caller.id && !is_admin

    User.where(id:).update_all(email:, full_name:, is_active:, is_admin:)
  end

  def set_password(id, b)
    password = b.required_str("password")
    get(id)
    check_password(password)
    User.where(id:).update_all(password_hash: Auth.hash_password(password))
    LoginSession.where(user_id: id).delete_all
  end

  # The out-of-band bootstrap: create or reset a user (spec/api.md §3).
  def add(email, full_name, password, admin: true)
    email = check_email(email)
    check_password(password)
    u = User.find_or_initialize_by(email:)
    u.update!(full_name:, password_hash: Auth.hash_password(password), is_active: true, is_admin: admin)
  end
end
