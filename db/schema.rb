# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_11_000000) do
  create_table "analyst_picks", force: :cascade do |t|
    t.string "analyst_name", null: false
    t.string "confidence"
    t.boolean "correct"
    t.datetime "created_at", null: false
    t.datetime "evaluated_at"
    t.string "pick_side", null: false
    t.text "rationale"
    t.integer "report_id", null: false
    t.datetime "updated_at", null: false
    t.index ["analyst_name"], name: "index_analyst_picks_on_analyst_name"
    t.index ["correct"], name: "index_analyst_picks_on_correct"
    t.index ["report_id", "analyst_name"], name: "index_analyst_picks_on_report_id_and_analyst_name", unique: true
    t.index ["report_id"], name: "index_analyst_picks_on_report_id"
  end

  create_table "analyst_weights", force: :cascade do |t|
    t.decimal "accuracy", precision: 5, scale: 3
    t.string "analyst_name", null: false
    t.datetime "created_at", null: false
    t.date "last_backtest_date"
    t.text "notes"
    t.integer "sample_size"
    t.string "signal_type"
    t.datetime "updated_at", null: false
    t.decimal "weight", precision: 4, scale: 2
    t.index ["analyst_name"], name: "index_analyst_weights_on_analyst_name", unique: true
  end

  create_table "conversion_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "event_name", null: false
    t.json "metadata", default: {}
    t.datetime "occurred_at", null: false
    t.string "path"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["event_name"], name: "index_conversion_events_on_event_name"
    t.index ["occurred_at"], name: "index_conversion_events_on_occurred_at"
    t.index ["user_id"], name: "index_conversion_events_on_user_id"
  end

  create_table "game_results", force: :cascade do |t|
    t.integer "away_score"
    t.decimal "closing_spread", precision: 4, scale: 1
    t.decimal "closing_total", precision: 5, scale: 1
    t.datetime "created_at", null: false
    t.integer "game_id", null: false
    t.integer "home_score"
    t.datetime "lines_captured_at"
    t.integer "margin"
    t.decimal "opening_spread", precision: 4, scale: 1
    t.decimal "opening_total", precision: 5, scale: 1
    t.datetime "result_captured_at"
    t.boolean "spread_covered_home"
    t.string "spread_result"
    t.boolean "total_over"
    t.string "total_result"
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_game_results_on_game_id"
    t.index ["lines_captured_at"], name: "index_game_results_on_lines_captured_at"
    t.index ["spread_result"], name: "index_game_results_on_spread_result"
    t.index ["total_result"], name: "index_game_results_on_total_result"
  end

  create_table "games", force: :cascade do |t|
    t.string "away_abbr"
    t.string "away_edge"
    t.text "away_linescores"
    t.string "away_record"
    t.string "away_road_record"
    t.integer "away_score"
    t.decimal "away_spread"
    t.string "away_team"
    t.string "clock"
    t.datetime "created_at", null: false
    t.string "external_id"
    t.datetime "game_date"
    t.string "h2h_summary"
    t.string "home_abbr"
    t.string "home_edge"
    t.string "home_home_record"
    t.text "home_linescores"
    t.string "home_record"
    t.integer "home_score"
    t.decimal "home_spread"
    t.string "home_team"
    t.string "league"
    t.string "league_name"
    t.datetime "lines_captured_at"
    t.decimal "opening_spread", precision: 4, scale: 1
    t.decimal "opening_total", precision: 5, scale: 1
    t.integer "period"
    t.integer "public_home_pct"
    t.integer "public_over_pct"
    t.integer "rest_days"
    t.string "schedule_note"
    t.integer "sport_id", null: false
    t.decimal "spread_movement", precision: 3, scale: 1
    t.string "status"
    t.decimal "total_line"
    t.decimal "total_movement", precision: 3, scale: 1
    t.datetime "updated_at", null: false
    t.string "venue"
    t.index ["away_abbr"], name: "index_games_on_away_abbr"
    t.index ["external_id"], name: "index_games_on_external_id", unique: true
    t.index ["game_date"], name: "index_games_on_game_date"
    t.index ["home_abbr", "away_abbr", "game_date"], name: "index_games_on_home_abbr_and_away_abbr_and_game_date"
    t.index ["home_abbr"], name: "index_games_on_home_abbr"
    t.index ["league"], name: "index_games_on_league"
    t.index ["lines_captured_at"], name: "index_games_on_lines_captured_at"
    t.index ["sport_id", "game_date"], name: "index_games_on_sport_id_and_game_date"
    t.index ["sport_id"], name: "index_games_on_sport_id"
    t.index ["status"], name: "index_games_on_status"
  end

  create_table "insights", force: :cascade do |t|
    t.string "category"
    t.text "content"
    t.datetime "created_at", null: false
    t.string "meta_description"
    t.datetime "published_at"
    t.integer "report_id"
    t.integer "sport_id", null: false
    t.string "status"
    t.string "tags"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["published_at"], name: "index_insights_on_published_at"
    t.index ["report_id"], name: "index_insights_on_report_id"
    t.index ["report_id"], name: "index_insights_on_report_id_unique", unique: true, where: "report_id IS NOT NULL"
    t.index ["sport_id", "status"], name: "index_insights_on_sport_id_and_status"
    t.index ["sport_id"], name: "index_insights_on_sport_id"
    t.index ["status"], name: "index_insights_on_status"
  end

  create_table "picks", force: :cascade do |t|
    t.json "analysis_data"
    t.integer "confidence", null: false
    t.datetime "created_at", null: false
    t.decimal "edge_score", precision: 4, scale: 1, null: false
    t.string "engine_version"
    t.integer "game_id", null: false
    t.decimal "line_at_pick", precision: 5, scale: 1
    t.decimal "odds_at_pick", precision: 5, scale: 2
    t.string "pick_side", null: false
    t.string "pick_team"
    t.string "pick_type", null: false
    t.decimal "profit", precision: 4, scale: 2
    t.datetime "published_at"
    t.string "result"
    t.datetime "result_recorded_at"
    t.string "signal", null: false
    t.string "status", default: "draft"
    t.decimal "units", precision: 3, scale: 1, default: "1.0"
    t.datetime "updated_at", null: false
    t.index ["game_id", "pick_type"], name: "index_picks_on_game_id_and_pick_type", unique: true
    t.index ["game_id"], name: "index_picks_on_game_id"
    t.index ["pick_type", "result"], name: "index_picks_on_type_and_result"
    t.index ["pick_type"], name: "index_picks_on_pick_type"
    t.index ["published_at"], name: "index_picks_on_published_at"
    t.index ["result"], name: "index_picks_on_result"
    t.index ["signal", "result"], name: "index_picks_on_signal_and_result"
    t.index ["signal"], name: "index_picks_on_signal"
    t.index ["status"], name: "index_picks_on_status"
  end

  create_table "reports", force: :cascade do |t|
    t.integer "actual_away_score"
    t.integer "actual_home_score"
    t.string "analyst_consensus"
    t.text "claude_analysis"
    t.string "confidence"
    t.string "consensus_pick"
    t.text "content"
    t.datetime "created_at", null: false
    t.boolean "free", default: false
    t.integer "game_id", null: false
    t.text "gemini_analysis"
    t.text "gpt_analysis"
    t.json "instagram_images"
    t.string "pick"
    t.decimal "pick_line"
    t.string "pick_side"
    t.string "pick_type"
    t.datetime "published_at"
    t.string "result"
    t.text "result_note"
    t.datetime "result_recorded_at"
    t.datetime "social_generated_at"
    t.decimal "stake", default: "1.0"
    t.string "status"
    t.json "structured_data"
    t.string "title"
    t.json "twitter_thread"
    t.datetime "updated_at", null: false
    t.text "youtube_shorts_script"
    t.index ["free"], name: "index_reports_on_free"
    t.index ["game_id", "status"], name: "index_reports_on_game_id_and_status"
    t.index ["game_id"], name: "index_reports_on_game_id"
    t.index ["pick_type"], name: "index_reports_on_pick_type"
    t.index ["published_at"], name: "index_reports_on_published_at"
    t.index ["result", "pick_type"], name: "index_reports_on_result_and_pick_type"
    t.index ["result"], name: "index_reports_on_result"
    t.index ["status"], name: "index_reports_on_status"
  end

  create_table "sports", force: :cascade do |t|
    t.boolean "active"
    t.datetime "created_at", null: false
    t.string "icon"
    t.string "name"
    t.integer "position"
    t.string "slug"
    t.datetime "updated_at", null: false
  end

  create_table "subscriptions", force: :cascade do |t|
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.text "note"
    t.string "payment_id"
    t.string "payment_method"
    t.datetime "payment_requested_at"
    t.string "plan", null: false
    t.json "request_metadata", default: {}
    t.datetime "reviewed_at"
    t.string "reviewed_by"
    t.datetime "starts_at", null: false
    t.string "status", default: "active"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["expires_at"], name: "index_subscriptions_on_expires_at"
    t.index ["payment_requested_at"], name: "index_subscriptions_on_payment_requested_at"
    t.index ["reviewed_at"], name: "index_subscriptions_on_reviewed_at"
    t.index ["status"], name: "index_subscriptions_on_status"
    t.index ["user_id", "status"], name: "index_subscriptions_on_user_id_and_status"
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "last_sign_in_at"
    t.string "name"
    t.string "password_digest", null: false
    t.string "role", default: "user"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "weakness_predictions", force: :cascade do |t|
    t.string "actual_outcome"
    t.float "confidence"
    t.datetime "created_at", null: false
    t.datetime "evaluated_at"
    t.integer "game_id", null: false
    t.boolean "hit"
    t.string "predicted_outcome"
    t.string "source"
    t.string "team", null: false
    t.string "trigger_detail"
    t.string "trigger_type", null: false
    t.datetime "triggered_at"
    t.datetime "updated_at", null: false
    t.index ["evaluated_at"], name: "index_weakness_predictions_on_evaluated_at"
    t.index ["game_id"], name: "index_weakness_predictions_on_game_id"
    t.index ["team", "trigger_type"], name: "index_weakness_predictions_on_team_and_trigger_type"
    t.index ["trigger_type", "hit"], name: "index_weakness_predictions_on_trigger_type_and_hit"
  end

  add_foreign_key "analyst_picks", "reports"
  add_foreign_key "conversion_events", "users"
  add_foreign_key "game_results", "games"
  add_foreign_key "games", "sports"
  add_foreign_key "insights", "sports"
  add_foreign_key "picks", "games"
  add_foreign_key "reports", "games"
  add_foreign_key "subscriptions", "users"
  add_foreign_key "weakness_predictions", "games"
end
