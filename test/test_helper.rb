ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module G9TestDataHelper
  def create_sport(slug: "basketball")
    Sport.create!(
      name: slug.titleize,
      slug: slug,
      active: true,
      position: 1
    )
  end

  def create_game(sport:, starts_at: 1.day.from_now)
    Game.create!(
      sport: sport,
      home_team: "Home Team",
      away_team: "Away Team",
      home_abbr: "HOME",
      away_abbr: "AWAY",
      game_date: starts_at
    )
  end

  def create_report(game:, free: false, result: "win")
    Report.create!(
      game: game,
      title: "Signal Report",
      content: "Premium analysis content",
      pick: "HOME -3.5",
      confidence: "4",
      free: free,
      status: "published",
      published_at: Time.current,
      result: result,
      result_recorded_at: Time.current
    )
  end

  def create_user(email: "user@example.com", password: "password123", role: "user")
    User.create!(
      email: email,
      password: password,
      password_confirmation: password,
      role: role
    )
  end

  def sign_in_as(user, password: "password123")
    post sign_in_path, params: { email: user.email, password: password }
  end

  def sign_in_admin(password: "secret-token")
    old_token = ENV["ADMIN_TOKEN"]
    ENV["ADMIN_TOKEN"] = password
    post admin_login_path, params: { password: password }
    yield
  ensure
    ENV["ADMIN_TOKEN"] = old_token
  end
end

class ActiveSupport::TestCase
  parallelize(workers: 1)
  include G9TestDataHelper
end

class ActionDispatch::IntegrationTest
  include G9TestDataHelper
end
