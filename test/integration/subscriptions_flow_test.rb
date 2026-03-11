require "test_helper"

class SubscriptionsFlowTest < ActionDispatch::IntegrationTest
  test "creating a subscription request persists pending payment and conversion event" do
    create_sport
    user = create_user

    sign_in_as(user)

    assert_difference("Subscription.pending_payment.count", 1) do
      assert_difference("ConversionEvent.where(event_name: 'payment_requested').count", 1) do
        post subscriptions_path, params: { plan: "monthly", source_path: "/basketball/reports/1" }
      end
    end

    assert_response :success
    subscription = user.subscriptions.order(:created_at).last
    assert_equal "pending_payment", subscription.status
    assert_equal "/basketball/reports/1", subscription.request_metadata["source_path"]
  end
end
