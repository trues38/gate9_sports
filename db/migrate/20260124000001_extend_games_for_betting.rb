# frozen_string_literal: true

class ExtendGamesForBetting < ActiveRecord::Migration[8.1]
  def change
    change_table :games, bulk: true do |t|
      # 오프닝 라인 (ESPN에서 처음 수집된 라인)
      t.decimal :opening_spread, precision: 4, scale: 1
      t.decimal :opening_total, precision: 5, scale: 1

      # 라인 무브먼트 (closing - opening)
      t.decimal :spread_movement, precision: 3, scale: 1
      t.decimal :total_movement, precision: 3, scale: 1

      # 퍼블릭 베팅 비율 (Sharp 역지표용)
      t.integer :public_home_pct  # 홈팀 베팅 비율 (0-100)
      t.integer :public_over_pct  # 오버 베팅 비율 (0-100)

      # 라인 캡처 시점
      t.datetime :lines_captured_at
    end

    add_index :games, :lines_captured_at
  end
end
