defmodule Teiserver.Telemetry.AnonPropertyQueries do
  @moduledoc false
  use CentralWeb, :queries
  alias Teiserver.Telemetry.AnonProperty

  # Queries
  @spec query_anon_properties(list) :: Ecto.Query.t()
  def query_anon_properties(args) do
    query = from(anon_properties in AnonProperty)

    query
    |> do_where([id: args[:id]])
    |> do_where(args[:where])
    |> do_preload(args[:preload])
    |> do_order_by(args[:order_by])
    |> query_select(args[:select])
  end

  @spec do_where(Ecto.Query.t(), list | map | nil) :: Ecto.Query.t()
  defp do_where(query, nil), do: query

  defp do_where(query, params) do
    params
    |> Enum.reduce(query, fn {key, value}, query_acc ->
      _where(query_acc, key, value)
    end)
  end

  @spec _where(Ecto.Query.t(), Atom.t(), any()) :: Ecto.Query.t()
  defp _where(query, _, ""), do: query
  defp _where(query, _, nil), do: query

  defp _where(query, :id, id) do
    from anon_properties in query,
      where: anon_properties.id == ^id
  end

  defp _where(query, :between, {start_date, end_date}) do
    from anon_properties in query,
      where: between(anon_properties.timestamp, ^start_date, ^end_date)
  end

  defp _where(query, :event_type_id, event_type_id) do
    from anon_properties in query,
      where: anon_properties.event_type_id == ^event_type_id
  end

  defp _where(query, :event_type_id_in, event_type_ids) do
    from anon_properties in query,
      where: anon_properties.event_type_id in ^event_type_ids
  end

  @spec do_order_by(Ecto.Query.t(), list | nil) :: Ecto.Query.t()
  defp do_order_by(query, nil), do: query
  defp do_order_by(query, params) do
    params
    |> Enum.reduce(query, fn key, query_acc ->
      _order_by(query_acc, key)
    end)
  end

  defp _order_by(query, nil), do: query

  defp _order_by(query, "Newest first") do
    from anon_properties in query,
      order_by: [desc: anon_properties.timestamp]
  end

  defp _order_by(query, "Oldest first") do
    from anon_properties in query,
      order_by: [asc: anon_properties.timestamp]
  end

  @spec do_preload(Ecto.Query.t(), List.t() | nil) :: Ecto.Query.t()
  defp do_preload(query, nil), do: query

  defp do_preload(query, preloads) do
    preloads
    |> Enum.reduce(query, fn key, query_acc ->
      _preload(query_acc, key)
    end)
  end

  def _preload(query, :property_type) do
    from anon_properties in query,
      left_join: property_types in assoc(anon_properties, :property_type),
      preload: [property_type: property_types]
  end

  def _preload(query, :users) do
    from anon_properties in query,
      left_join: users in assoc(anon_properties, :user),
      preload: [user: users]
  end

  @spec get_anon_properties_summary(list) :: map()
  def get_anon_properties_summary(args) do
    query =
      from anon_properties in AnonProperty,
        join: event_types in assoc(anon_properties, :event_type),
        group_by: event_types.name,
        select: {event_types.name, count(anon_properties.event_type_id)}

    query
    |> do_where(args)
    |> Repo.all()
    |> Map.new()
  end
end