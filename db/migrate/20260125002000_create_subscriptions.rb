class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :plan, null: false        # daily, weekly, monthly
      t.integer :amount, null: false     # 결제 금액 (원)
      t.string :payment_method           # toss, kakao, manual
      t.string :payment_id               # 외부 결제 ID
      t.datetime :starts_at, null: false
      t.datetime :expires_at, null: false
      t.string :status, default: "active"  # active, expired, cancelled
      t.text :note
      t.timestamps
    end

    add_index :subscriptions, [:user_id, :status]
    add_index :subscriptions, :expires_at
    add_index :subscriptions, :status
  end
end
