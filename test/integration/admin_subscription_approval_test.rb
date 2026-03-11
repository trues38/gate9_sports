require "test_helper"

class AdminSubscriptionApprovalTest < ActionDispatch::IntegrationTest
  test "admin approves pending payment and logs conversion event" do
    create_sport
    user = create_user
    subscription = Subscription.create_payment_request!(user: user, plan: "weekly")

    sign_in_admin do
      assert_difference("ConversionEvent.where(event_name: 'payment_approved').count", 1) do
        post approve_admin_subscription_path(subscription)
      end
    end

    assert_redirected_to admin_subscriptions_path(locale: I18n.default_locale)
    subscription.reload
    assert_equal "active", subscription.status
  end
end
