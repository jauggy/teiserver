defmodule Teiserver.Battle.SplitOneChevsTest do
  @moduledoc """
  Can run all balance tests via
  mix test --only balance_test
  """
  use ExUnit.Case
  @moduletag :balance_test
  alias Teiserver.Battle.BalanceLib

  # Define constants
  @split_algo "split_one_chevs"

  test "split one chevs empty" do
    result =
      BalanceLib.create_balance(
        [],
        4,
        algorithm: @split_algo
      )

    assert result == %{
             logs: [],
             ratings: %{},
             time_taken: 0,
             captains: %{},
             deviation: 0,
             team_groups: %{},
             team_players: %{},
             team_sizes: %{},
             means: %{},
             stdevs: %{},
             has_parties?: false
           }
  end

  test "split one chevs FFA" do
    result =
      BalanceLib.create_balance(
        [
          %{1 => %{rating: 5, rank_time: 15}},
          %{2 => %{rating: 6, rank_time: 15}},
          %{3 => %{rating: 7, rank_time: 15}},
          %{4 => %{rating: 8, rank_time: 15}}
        ],
        4,
        algorithm: @split_algo
      )

    assert result.team_players == %{1 => [4], 2 => [3], 3 => [2], 4 => [1]}
  end

  test "split one chevs team FFA" do
    result =
      BalanceLib.create_balance(
        [
          %{1 => %{rating: 5, rank_time: 15}},
          %{2 => %{rating: 6, rank_time: 15}},
          %{3 => %{rating: 7, rank_time: 15}},
          %{4 => %{rating: 8, rank_time: 15}},
          %{5 => %{rating: 9, rank_time: 15}},
          %{6 => %{rating: 9, rank_time: 15}}
        ],
        3,
        algorithm: @split_algo
      )

    assert result.team_players == %{1 => [1, 5], 2 => [2, 6], 3 => [3, 4]}
  end

  test "split one chevs simple group" do
    result =
      BalanceLib.create_balance(
        [
          %{4 => %{rating: 5, rank_time: 15}, 1 => %{rating: 8, rank_time: 15}},
          %{2 => %{rating: 6, rank_time: 15}},
          %{3 => %{rating: 7, rank_time: 15}}
        ],
        2,
        rating_lower_boundary: 100,
        rating_upper_boundary: 100,
        mean_diff_max: 100,
        stddev_diff_max: 100,
        algorithm: @split_algo
      )

    assert result.team_players == %{1 => [4, 1], 2 => [2, 3]}
  end

  test "logs FFA" do
    result =
      BalanceLib.create_balance(
        [
          %{"Pro1" => %{rating: 5, rank: 1, rank_time: 15}},
          %{"Pro2" => %{rating: 6, rank: 1, rank_time: 15}},
          %{"Noob1" => %{rating: 7, rank: 0, rank_time: 1}},
          %{"Noob2" => %{rating: 8, rank: 0, rank_time: 1}}
        ],
        4,
        algorithm: @split_algo
      )

    assert result.logs == [
             "Algorithm: split_one_chevs",
             "---------------------------",
             "Your team will try and avoid picking one chevs and prefer picking players with higher Adjusted Rating. Adjusted Rating starts at 0 and converges towards OS over time. Once a player hits three chevrons, Adjusted Rating just equals OS.",
             "---------------------------",
             "Pro2 (6, Chev: 2) picked for Team 1",
             "Pro1 (5, Chev: 2) picked for Team 2",
             "Noob2 (0.5, Chev: 1) picked for Team 3",
             "Noob1 (0.5, Chev: 1) picked for Team 4"
           ]
  end

  test "logs Team" do
    result =
      BalanceLib.create_balance(
        [
          %{"Pro1" => %{rating: 5, rank: 1, rank_time: 15}},
          %{"Pro2" => %{rating: 6, rank: 1, rank_time: 15}},
          %{"Noob1" => %{rating: 7, rank: 0, rank_time: 1}},
          %{"Noob2" => %{rating: 8, rank: 0, rank_time: 1}}
        ],
        2,
        algorithm: @split_algo
      )

    assert result.logs == [
             "Algorithm: split_one_chevs",
             "---------------------------",
             "Your team will try and avoid picking one chevs and prefer picking players with higher Adjusted Rating. Adjusted Rating starts at 0 and converges towards OS over time. Once a player hits three chevrons, Adjusted Rating just equals OS.",
             "---------------------------",
             "Pro2 (6, Chev: 2) picked for Team 1",
             "Pro1 (5, Chev: 2) picked for Team 2",
             "Noob2 (0.5, Chev: 1) picked for Team 2",
             "Noob1 (0.5, Chev: 1) picked for Team 1"
           ]
  end
end
