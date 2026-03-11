class AddReportIdToInsights < ActiveRecord::Migration[8.1]
  def change
    add_column :insights, :report_id, :integer
    add_column :insights, :meta_description, :string
    add_index :insights, :report_id
    add_index :insights, :report_id, unique: true, name: "index_insights_on_report_id_unique",
              where: "report_id IS NOT NULL"
  end
end
