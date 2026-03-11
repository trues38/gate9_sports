require "test_helper"

class ReportsPaywallTest < ActionDispatch::IntegrationTest
  test "premium report view logs paywall event for guests" do
    sport = create_sport
    game = create_game(sport: sport)
    report = create_report(game: game, free: false)

    assert_difference("ConversionEvent.where(event_name: 'paywall_viewed').count", 1) do
      get report_path(report, sport: sport.slug)
    end

    assert_redirected_to sign_in_path(locale: I18n.default_locale)
  end
end
