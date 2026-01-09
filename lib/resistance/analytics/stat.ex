defmodule Resistance.Analytics.Stat do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "analytics_stats" do
    field :metric_name, :string
    field :count, :integer
    field :last_updated, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(stat, attrs) do
    stat
    |> cast(attrs, [:metric_name, :count, :last_updated])
    |> validate_required([:metric_name, :count, :last_updated])
    |> unique_constraint(:metric_name)
  end
end
