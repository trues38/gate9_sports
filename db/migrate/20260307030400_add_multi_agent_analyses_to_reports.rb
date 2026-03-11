class AddMultiAgentAnalysesToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :gpt_analysis, :text
    add_column :reports, :gemini_analysis, :text
    add_column :reports, :claude_analysis, :text
    add_column :reports, :consensus_pick, :string
  end
end
