defmodule Teiserver.Battle.ProvisionalRatingLibTest do
  use ExUnit.Case
  @moduletag :balance_test
  alias Teiserver.Battle.Balance.ProvisionalRatingLib

  test "adjust_rating_from_hours" do
    ratings = [10, 10, 10, 10, 10, -1]
    rank_time = [0, 7.5, 20, 3.75, 21, 7.5]
    result = ProvisionalRatingLib.adjust_rating_from_hours(ratings, rank_time)

    assert result == [0, 5, 10, 2.5, 10, -0.5]
  end

  test "apply_provisional_ratings" do
    expanded_group = [
      %{
        count: 2,
        members: ["Pro1", "Noob1"],
        group_rating: 13,
        ratings: [8, 5],
        ranks: [1, 0],
        names: ["Pro1", "Noob1"],
        rank_times: [20, 1]
      },
      %{
        count: 1,
        members: ["Noob2"],
        group_rating: 6,
        ratings: [6],
        ranks: [0],
        names: ["Noob2"],
        rank_times: [10]
      },
      %{
        count: 1,
        members: ["Noob3"],
        group_rating: 7,
        ratings: [17],
        ranks: [0],
        names: ["Noob3"],
        rank_times: [10]
      }
    ]

    result = ProvisionalRatingLib.apply_provisional_ratings(expanded_group)

    assert result == [
             %{
               count: 2,
               group_rating: 8.333333333333334,
               members: ["Pro1", "Noob1"],
               names: ["Pro1", "Noob1"],
               rank_times: [20, 1],
               ranks: [1, 0],
               ratings: [8, 0.3333333333333333]
             },
             %{
               count: 1,
               group_rating: 4.0,
               members: ["Noob2"],
               names: ["Noob2"],
               rank_times: [10],
               ranks: [0],
               ratings: [4.0]
             },
             %{
               count: 1,
               group_rating: 11.333333333333332,
               members: ["Noob3"],
               names: ["Noob3"],
               rank_times: [10],
               ranks: [0],
               ratings: [11.333333333333332]
             }
           ]
  end
end
