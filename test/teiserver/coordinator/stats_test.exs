defmodule Teiserver.Coordinator.StatsTest do
  use ExUnit.Case
  import Mock
  alias Teiserver.Account
  alias Teiserver.CacheUser
  alias Teiserver.Game.MatchRatingLib
  alias Teiserver.Coordinator.CoordinatorCommands

  # These functions hit the database so we will mock them instead
  setup_with_mocks([
    {CacheUser, [:passthrough],
     [
       get_user_by_id: fn member_id -> get_user(member_id) end,
       get_user_by_name: fn name -> get_user(name) end,
       send_direct_message: fn _x, _y, _z -> nil end
     ]},
    {
      Account,
      [:passthrough],
      [list_ratings: fn rating_type_id -> list_ratings(rating_type_id) end]
    },
    {
      MatchRatingLib,
      [:passthrough],
      [rating_type_name_lookup: fn -> %{"Team" => 2, "Duel" => 1} end]
    }
  ]) do
    :ok
  end

  test "mocks" do
    assert 2 == MatchRatingLib.rating_type_name_lookup()["Team"]
    assert 1 == MatchRatingLib.rating_type_name_lookup()["Duel"]
  end

  test "Ask non-existant user" do
    result = CoordinatorCommands.send_stats_messages("John", "Team", 0, %{userid: 0})

    assert result == {:error, "Unable to find a user with that name"}
  end

  test "send team stats_messages" do
    result = CoordinatorCommands.send_stats_messages("Joshua", "Team", 0, %{userid: 0})

    assert result ==
             {:ok,
              %{
                leaderboard_rating: 8.0,
                os: 20.0,
                percentile: 25,
                rank: 1,
                rating_type: "Team",
                skill: 26.0,
                uncertainty: 6.0,
                username: "Joshua"
              }}
  end

  test "send duel stats_messages" do
    result = CoordinatorCommands.send_stats_messages("Joshua", "Duel", 0, %{})
    assert result == {:error, "Joshua doesn't have a recent Duel Rating"}
  end

  test "send FFA stats_messages" do
    result = CoordinatorCommands.send_stats_messages("Joshua", "FFA", 0, %{})
    assert result == {:error, "Joshua doesn't have a recent FFA Rating"}
  end

  # Mocks
  defp get_user(name) do
    case name do
      "Joshua" ->
        %{
          id: 42,
          name: "Joshua"
        }

      _ ->
        nil
    end
  end

  defp list_ratings(opts) do
    rating_type_id = opts[:search][:rating_type_id]

    cond do
      # DUel
      rating_type_id == 1 ->
        []

      # Team
      rating_type_id == 2 ->
        [
          %{
            user_id: 42,
            rating_type_id: 1,
            rating_value: 20.0,
            skill: 26.0,
            uncertainty: 6.0,
            leaderboard_rating: 8.0,
            last_updated: ~U[2024-03-22 08:36:06Z]
          },
          %{
            user_id: 43,
            rating_type_id: 1,
            rating_value: 17.0,
            skill: 23.0,
            uncertainty: 6.0,
            leaderboard_rating: 5.0,
            last_updated: ~U[2024-03-22 08:36:06Z]
          },
          %{
            user_id: 44,
            rating_type_id: 1,
            rating_value: 17.0,
            skill: 23.0,
            uncertainty: 6.0,
            leaderboard_rating: 5.0,
            last_updated: ~U[2024-03-22 08:36:06Z]
          },
          %{
            user_id: 41,
            rating_type_id: 1,
            rating_value: 15.0,
            skill: 21.0,
            uncertainty: 6.0,
            leaderboard_rating: 3.0,
            last_updated: ~U[2024-03-22 08:36:06Z]
          }
        ]

      # Anything else
      true ->
        []
    end
  end
end
