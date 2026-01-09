defmodule Resistance.Repo.Migrations.CreateAnalyticsStats do
  use Ecto.Migration

  def change do
    create table(:analytics_stats, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :metric_name, :string, null: false
      add :count, :bigint, null: false, default: 0
      add :last_updated, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:analytics_stats, [:metric_name])

    # Initialize the five metrics
    execute """
      INSERT INTO analytics_stats (id, metric_name, count, last_updated, inserted_at, updated_at)
      VALUES
        (gen_random_uuid(), 'site_visits', 0, NOW(), NOW(), NOW()),
        (gen_random_uuid(), 'rooms_created', 0, NOW(), NOW(), NOW()),
        (gen_random_uuid(), 'games_started', 0, NOW(), NOW(), NOW()),
        (gen_random_uuid(), 'good_team_wins', 0, NOW(), NOW(), NOW()),
        (gen_random_uuid(), 'bad_team_wins', 0, NOW(), NOW(), NOW())
    """, """
      DELETE FROM analytics_stats WHERE metric_name IN (
        'site_visits', 'rooms_created', 'games_started', 'good_team_wins', 'bad_team_wins'
      )
    """
  end
end
