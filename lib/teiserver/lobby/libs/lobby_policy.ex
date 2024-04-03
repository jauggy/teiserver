defmodule Teiserver.Lobby.LobbyPolicy do
  @moduledoc """
  Helper methods for lobby policies
  """
  alias Teiserver.CacheUser
  require Logger
  alias Teiserver.Battle.BalanceLib

  @rank_upper_bound 1000
  @rating_upper_bound 1000
  @splitter "---------------------------"
  @spec rank_upper_bound() :: number
  def rank_upper_bound, do: @rank_upper_bound
  def rating_upper_bound, do: @rating_upper_bound

  def get_rating_bounds_text(state) do
    min_rate_play = state.minimum_rating_to_play
    max_rate_play = state.maximum_rating_to_play

    play_level_bounds =
      cond do
        min_rate_play > 0 and max_rate_play < @rating_upper_bound ->
          "Play rating boundaries set to min: #{min_rate_play}, max: #{max_rate_play}"

        min_rate_play > 0 ->
          "Play rating boundaries set to min: #{min_rate_play}"

        max_rate_play < @rating_upper_bound ->
          "Play rating boundaries set to max: #{max_rate_play}"

        true ->
          nil
      end

    play_level_bounds
  end

  @spec get_rank_bounds_text(
          atom()
          | %{
              :maximum_rank_to_play => number(),
              :minimum_rank_to_play => number(),
              optional(any()) => any()
            }
        ) :: nil | <<_::64, _::_*8>>
  def get_rank_bounds_text(state) do
    min_rank_play = state.minimum_rank_to_play
    max_rank_play = state.maximum_rank_to_play
    min_chev = min_rank_play + 1
    max_chev = max_rank_play + 1

    play_rank_bounds =
      cond do
        min_rank_play > 0 and max_rank_play < @rank_upper_bound ->
          "Chev boundaries set to min: #{min_chev}, max: #{max_chev}"

        min_rank_play > 0 ->
          "Chev boundaries set to min: #{min_chev}"

        max_rank_play < @rank_upper_bound ->
          "Chev boundaries set to max: #{max_chev}"

        true ->
          nil
      end

    play_rank_bounds
  end

  def get_rank_bounds_for_title(consul_state) do
    # Chevlevel stuff here
    cond do
      consul_state == nil ->
        nil

      # Default chev levels
      consul_state.maximum_rank_to_play >= @rank_upper_bound &&
          consul_state.minimum_rank_to_play <= 0 ->
        nil

      # Just a max rating
      consul_state.maximum_rank_to_play < @rank_upper_bound &&
          consul_state.minimum_rank_to_play <= 0 ->
        "Max chev: #{consul_state.maximum_rank_to_play + 1}"

      # Just a min rating
      consul_state.maximum_rank_to_play >= @rank_upper_bound &&
          consul_state.minimum_rank_to_play > 0 ->
        "Min chev: #{consul_state.minimum_rank_to_play + 1}"

      # Rating range
      consul_state.maximum_rank_to_play < @rank_upper_bound ||
          consul_state.minimum_rank_to_play > 0 ->
        "Chev between: #{consul_state.minimum_rank_to_play + 1} - #{consul_state.maximum_rank_to_play + 1}"

      true ->
        nil
    end
  end

  def get_rating_bounds_for_title(consul_state) do
    cond do
      consul_state == nil ->
        nil

      # Default ratings
      consul_state.maximum_rating_to_play >= 1000 &&
          consul_state.minimum_rating_to_play <= 0 ->
        nil

      # Just a max rating
      consul_state.maximum_rating_to_play < 1000 &&
          consul_state.minimum_rating_to_play <= 0 ->
        "Max rating: #{consul_state.maximum_rating_to_play}"

      # Just a min rating
      consul_state.maximum_rating_to_play >= 1000 &&
          consul_state.minimum_rating_to_play > 0 ->
        "Min rating: #{consul_state.minimum_rating_to_play}"

      # Rating range
      consul_state.maximum_rating_to_play < 1000 ||
          consul_state.minimum_rating_to_play > 0 ->
        "Rating between: #{consul_state.minimum_rating_to_play} - #{consul_state.maximum_rating_to_play}"

      true ->
        nil
    end
  end

  def get_failed_rank_check_text(player_rank, consul_state) do
    bounds = get_rank_bounds_for_title(consul_state)
    [@splitter,
    "You don't meet the chevron requirements for this lobby (#{bounds}). Your chevron level is #{player_rank + 1}. Learn more about chevrons here:",
    "https://www.beyondallreason.info/guide/rating-and-lobby-balance#rank-icons"]
  end

  def get_failed_rating_check_text(player_rating, consul_state, rating_type) do
    bounds = get_rating_bounds_for_title(consul_state)
    player_rating_text = player_rating |> Decimal.from_float() |> Decimal.round(2)
    [@splitter,
    "You don't meet the rating requirements for this lobby (#{bounds}). Your #{rating_type} match rating is #{player_rating_text}. Learn more about rating here:",
    "https://www.beyondallreason.info/guide/rating-and-lobby-balance#openskill"]
  end

  @spec check_rank_to_play(non_neg_integer() | map(), any()) ::
          {false, [<<_::64, _::_*8>>, ...]} | {true, nil}
  @doc """
  Returns {check_passed?, msg}
  """
  def check_rank_to_play(user, consul_state) do
    state= consul_state
    # Contributors auto pass since their ranks are messed up
    is_contributor? = CacheUser.is_contributor?(user)

    if is_contributor? do
      {true, nil}
    else
      cond do
        state.minimum_rank_to_play != nil and user.rank < state.minimum_rank_to_play ->
          # Send message
          msg = get_failed_rank_check_text(user.rank, state)
          {false, msg}


        state.maximum_rank_to_play != nil and user.rank > state.maximum_rank_to_play ->
          # Send message
          msg = get_failed_rank_check_text(user.rank, state)
          {false, msg}

        true ->
          {true, nil}
      end
    end
  end

  @doc """
  Returns {check_passed?, msg}
  """
  def check_rating_to_play(user_id, consul_state) do
    team_size = consul_state.host_teamsize

    #team_count = consul_state.host_teamcount
    state  = consul_state
    rating_type = cond do
      team_size == 1 -> "Duel"
      true -> "Team"
    end

    {player_rating, player_uncertainty} =
      BalanceLib.get_user_rating_value_uncertainty_pair(user_id, rating_type)

    player_rating = max(player_rating, 1)


    cond do
      state.minimum_rating_to_play != nil and player_rating < state.minimum_rating_to_play ->
        msg = get_failed_rating_check_text(player_rating, state, rating_type)
        {false, msg}

      state.maximum_rating_to_play != nil and player_rating > state.maximum_rating_to_play ->
        msg = get_failed_rating_check_text(player_rating, state, rating_type)
        {false, msg}

      true ->
        # All good
        {true, nil}
    end
  end
end
