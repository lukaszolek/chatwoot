class CreateInfluencerHashtags < ActiveRecord::Migration[7.0]
  def change
    create_table :influencer_hashtags do |t|
      t.references :account, null: false, foreign_key: true
      t.string :tag, null: false
      t.string :language, null: false
      t.integer :profiles_count, default: 1
      t.boolean :starred, default: false
      t.integer :posts_count
      t.jsonb :apify_stats, default: {}
      t.datetime :stats_fetched_at
      t.timestamps
    end

    add_index :influencer_hashtags, %i[account_id tag language], unique: true, name: 'idx_hashtags_account_tag_lang'
    add_index :influencer_hashtags, %i[account_id language starred], name: 'idx_hashtags_lang_starred'
  end
end
