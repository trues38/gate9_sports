require "test_helper"

class AdminReportMediaTest < ActionDispatch::IntegrationTest
  test "admin can enqueue report media through adcraft client" do
    sport = create_sport
    game = create_game(sport: sport)
    report = create_report(game: game, free: true)
    original_method = AdcraftTaskClient.method(:enqueue_report_media!)

    sign_in_admin do
      AdcraftTaskClient.define_singleton_method(:enqueue_report_media!) do |_report|
        { "task_id" => "task-123" }
      end
      begin
        post create_media_admin_report_path(report)
      ensure
        AdcraftTaskClient.define_singleton_method(:enqueue_report_media!, original_method)
      end
    end

    assert_redirected_to admin_reports_path(locale: I18n.default_locale)
  end
end
