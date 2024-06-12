defmodule Teiserver.Battle.Balance.ProvisionalRatingLib do
  @moduledoc """
  This lib is only used by split_one_chevs balance algorithm
  """
  alias Teiserver.Battle.Balance.BalanceTypes, as: BT

  @doc """
  Users will have an adjusted rating that starts at 0 then converges to their OS as they accumulate chevron hours.
  Chevron hours was chosen because there are visual indicators of when players achieve certain thresholds.
  Chevron hours = playtime + spectime * 0.5
  Once they hit their third chevron, adjusted rating will just equal OS.
  """
  @spec adjust_rating_from_hours([float()], [float()]) :: any()
  def adjust_rating_from_hours(ratings, hours) do
    target_hours = 15.0
    zip_result = Enum.zip(ratings, hours)

    Enum.map(zip_result, fn {user_rating, user_hours} ->
      user_rating * min(1, user_hours / target_hours)
    end)
  end

  @doc """
  Function to assign provisional ratings to new users
  """
  @spec apply_provisional_ratings([BT.expanded_group()]) :: [BT.expanded_group()]
  def apply_provisional_ratings(expanded_group) do
    Enum.map(expanded_group, fn x ->
      new_ratings = adjust_rating_from_hours(x.ratings, x.rank_times)
      new_group_rating = Enum.sum(new_ratings)
      Map.merge(x, %{ratings: new_ratings, group_rating: new_group_rating})
    end)
  end
end
