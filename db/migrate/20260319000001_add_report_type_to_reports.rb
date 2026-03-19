class AddReportTypeToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :report_type, :string, default: "game_analysis", null: false
    change_column_null :reports, :game_id, true
    add_index :reports, :report_type
  end
end
