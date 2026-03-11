class AddManualPaymentWorkflowToSubscriptions < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :payment_requested_at, :datetime
    add_column :subscriptions, :reviewed_at, :datetime
    add_column :subscriptions, :reviewed_by, :string
    add_column :subscriptions, :request_metadata, :json, default: {}

    add_index :subscriptions, :payment_requested_at
    add_index :subscriptions, :reviewed_at
  end
end
