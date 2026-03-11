require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "create_payment_request stores pending request metadata" do
    user = create_user

    subscription = Subscription.create_payment_request!(
      user: user,
      plan: "monthly",
      request_metadata: { "source_path" => "/basketball/reports/1" }
    )

    assert_equal "pending_payment", subscription.status
    assert_equal "monthly", subscription.plan
    assert_equal "/basketball/reports/1", subscription.request_metadata["source_path"]
    assert_not_nil subscription.payment_requested_at
    assert_not subscription.active?
  end

  test "approve activates pending request and refreshes dates" do
    user = create_user
    subscription = Subscription.create_payment_request!(user: user, plan: "weekly")
    expected_start = Time.zone.parse("2026-03-06 12:00:00")
    expected_end = expected_start + 7.days

    travel_to expected_start do
      subscription.approve!(reviewed_by: "admin_session")
    end

    subscription.reload
    assert_equal "active", subscription.status
    assert_equal "admin_session", subscription.reviewed_by
    assert_equal expected_start, subscription.starts_at
    assert_equal expected_end.change(usec: 0), subscription.expires_at.change(usec: 0)
  end
end
