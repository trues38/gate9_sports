class AddLeagueToGames < ActiveRecord::Migration[8.1]
  def change
    add_column :games, :league, :string
    add_index :games, :league
    add_column :games, :league_name, :string
  end
end
