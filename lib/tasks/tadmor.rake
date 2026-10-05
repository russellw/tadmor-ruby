# Out-of-band commands: bin/rails tadmor:migrate, tadmor:adduser, tadmor:resetdb.
namespace :tadmor do
  desc "Apply pending shared-schema migrations (db/migrations)"
  task migrate: :environment do
    Migrations.apply.each { |v| puts "applied #{v}" }
  end

  desc "Create or reset an administrator: EMAIL=... NAME=... [ADMIN=0], password on stdin"
  task adduser: :environment do
    email, name = ENV["EMAIL"].to_s, ENV["NAME"].to_s
    abort "EMAIL and NAME are required" if email.strip.empty? || name.strip.empty?
    Migrations.apply
    password = $stdin.gets.to_s.chomp
    Users.add(email, name, password, admin: ENV["ADMIN"] != "0")
    puts "user #{email} is ready"
  rescue ApiError => e
    abort e.message
  end

  desc "Wipe a database whose name ends in _test or _conformance"
  task resetdb: :environment do
    puts "wiped database #{Migrations.reset!}"
  rescue ArgumentError => e
    abort e.message
  end
end
