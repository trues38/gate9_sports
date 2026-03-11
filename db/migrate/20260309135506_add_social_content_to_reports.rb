class AddSocialContentToReports < ActiveRecord::Migration[8.1]
  def change
    add_column :reports, :twitter_thread, :json
    add_column :reports, :youtube_shorts_script, :text
    add_column :reports, :instagram_images, :json
    add_column :reports, :social_generated_at, :datetime
  end
end
