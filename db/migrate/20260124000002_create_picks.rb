# frozen_string_literal: true

class CreatePicks < ActiveRecord::Migration[8.1]
  def change
    create_table :picks do |t|
      t.references :game, null: false, foreign_key: true

      # 픽 정보
      t.string :pick_type, null: false      # ML, SPREAD, TOTAL
      t.string :pick_side, null: false      # HOME, AWAY, OVER, UNDER
      t.string :pick_team                    # 팀 약어 (ML/SPREAD용)

      # 엔진 분석 결과
      t.decimal :edge_score, precision: 4, scale: 1, null: false
      t.integer :confidence, null: false    # 1-5
      t.string :signal, null: false         # STRONG_BET, BET, CAUTION, LEAN, PASS
      t.string :engine_version              # v2.3 등

      # 발행 시점 라인
      t.decimal :line_at_pick, precision: 5, scale: 1  # 스프레드 또는 토탈 라인
      t.decimal :odds_at_pick, precision: 5, scale: 2  # -110 등 (미래용)

      # 결과 추적
      t.string :result                       # win, loss, push, pending
      t.decimal :units, precision: 3, scale: 1, default: 1.0  # 베팅 단위
      t.decimal :profit, precision: 4, scale: 2              # 수익/손실

      # 분석 근거 (JSON)
      t.json :analysis_data
      # 예: {
      #   "factors": ["net_rtg_diff", "ats_trend", "rest_advantage"],
      #   "home_stats": {...},
      #   "away_stats": {...},
      #   "pattern_matched": "UNDERDOG_RESILIENCE"
      # }

      # 상태
      t.string :status, default: 'draft'     # draft, published, void
      t.datetime :published_at
      t.datetime :result_recorded_at

      t.timestamps
    end

    add_index :picks, [:game_id, :pick_type], unique: true
    add_index :picks, :pick_type
    add_index :picks, :signal
    add_index :picks, :result
    add_index :picks, :status
    add_index :picks, :published_at
    add_index :picks, [:pick_type, :result], name: 'index_picks_on_type_and_result'
    add_index :picks, [:signal, :result], name: 'index_picks_on_signal_and_result'
  end
end
