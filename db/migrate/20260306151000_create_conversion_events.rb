class CreateConversionEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :conversion_events do |t|
      t.references :user, null: true, foreign_key: true
      t.string :event_name, null: false
      t.string :path
      t.json :metadata, default: {}
      t.datetime :occurred_at, null: false

      t.timestamps
    end

    add_index :conversion_events, :event_name
    add_index :conversion_events, :occurred_at
  end
end
