defmodule Mix.Tasks.Teiserver.PredictionStats do
  @moduledoc """
  The purpose of this task is to get statistics on how well we predict the winner of a match. We use the BrierScore to measure prediction accuracy

  To run:

  mix teiserver.prediction_stats


  On integration server it is recommended you output to a specific path as follows:
  mix teiserver.prediction_stats /var/log/teiserver/prediction_results.txt
  """

  use Mix.Task
  require Logger
  alias Teiserver.Repo
  alias Teiserver.{Battle, Game}
  alias Teiserver.Battle.{BalanceLib}
  alias Mix.Tasks.Teiserver.PartyBalanceStatsTypes, as: PB
  alias Teiserver.Config

  @provisional_num_matches_cutoff 20

  def run(args) do
    Logger.info("Args: #{args}")
    write_log_filepath = Enum.at(args, 0, nil)

    Application.ensure_all_started(:teiserver)
    opts = []

    match_ids = get_match_ids()

    initial_errors = %{
      noob_matches: %{openskill_error: 0, bar_error: 0, provisional_error: 0, num_matches: 0},
      pro_matches: %{openskill_error: 0, bar_error: 0, provisional_error: 0, num_matches: 0}
    }

    # The error result will be the sum of forecast error squared for all matches
    error_result =
      Enum.map(match_ids, fn match_id -> get_match_forecast_error_squared(match_id) end)
      |> Enum.reduce(initial_errors, fn match_error, acc ->
        if(match_error.invalid_match?) do
          # Do not process
          acc
        else
          key = if match_error.has_noobs?, do: :noob_matches, else: :pro_matches

          # We simply add the errors for each match
          updated_errors = %{
            openskill_error: match_error.openskill_error + acc[key][:openskill_error],
            bar_error: match_error.bar_error + acc[key][:bar_error],
            provisional_error: match_error.provisional_error + acc[key][:provisional_error],
            num_matches: acc[key][:num_matches] + 1
          }

          Map.put(acc, key, updated_errors)
        end
      end)

    # The brier score is just the sum of error squared divided by num matches
    brier_score = %{
      noob_matches: convert_error_result_to_brier_score(error_result.noob_matches),
      pro_matches: convert_error_result_to_brier_score(error_result.pro_matches)
    }

    IO.inspect(brier_score, label: "brier_score", charlists: :as_lists)
    Logger.info("Finished processing matches")
  end

  defp convert_error_result_to_brier_score(
         %{
           openskill_error: openskill_error,
           bar_error: bar_error,
           provisional_error: provisional_error,
           num_matches: num_matches
         } = error_result
       ) do
    # Don't divide by zero

    if(num_matches == 0) do
      %{
        openskill_brier: 0,
        bar_brier: 0,
        provisional_brier: 0,
        num_matches: 0
      }
    else
      %{
        openskill_brier: openskill_error / num_matches,
        bar_brier: bar_error / num_matches,
        provisional_brier: provisional_error / num_matches,
        num_matches: num_matches
      }
    end
  end

  defp get_match_ids() do
    query = """
    select distinct  tbm.id, tbm.inserted_at  from
    teiserver_battle_matches tbm
    inner join teiserver_game_rating_logs tgrl
    on tgrl.match_id = tbm.id
    and tbm.team_size >= $1
    and tbm.team_count = $2
    and tgrl.value is not null
    order by tbm.inserted_at DESC
    limit 1000;

    """

    min_team_size = 2
    team_count = 2

    sql_results = Ecto.Adapters.SQL.query!(Repo, query, [min_team_size, team_count])

    sql_results.rows
    |> Enum.map(fn [id, _inserted] ->
      id
    end)
  end

  # This will return the forecast error squared using different rating system for a single match
  defp get_match_forecast_error_squared(match_id) do
    # This query will return players of this match
    # Sorted by win desc so that team 1 will always be the winning team
    # All log data is the postmatch value so we need to make adjustments to get prematch values
    query = """
    select team_id, win,
    (value->'skill')::float - (value->'skill_change')::float   as skill,
    (value->'uncertainty')::float - (value->'uncertainty_change')::float   as uncertainty,

    (value->'num_matches')::int - 1  as num_matches
    from teiserver_game_rating_logs tgrl
    inner join teiserver_battle_match_memberships tbmm
    on tbmm.match_id = tgrl.match_id
    and tbmm.match_id  = $1
    and tbmm.user_id  = tgrl.user_id

    order by win desc
    """

    sql_results = Ecto.Adapters.SQL.query!(Repo, query, [match_id])

    players =
      sql_results.rows
      |> Enum.map(fn [team_id, win, skill, uncertainty, num_matches] ->
        %{
          team_id: team_id,
          win: win,
          skill: skill,
          uncertainty: uncertainty,
          num_matches: num_matches
        }
      end)

    teams =
      players
      |> Enum.group_by(fn x -> x.team_id end)

    invalid_match? = players |> Enum.any?(fn x -> x.num_matches == nil end)

    if(invalid_match?) do
      %{
        invalid_match?: true
      }
    else
      has_noobs? =
        players |> Enum.any?(fn x -> x.num_matches < @provisional_num_matches_cutoff end)

      %{
        openskill_error: process_sql_result(teams, :openskill),
        bar_error: process_sql_result(teams, :bar),
        provisional_error: process_sql_result(teams, :provisional),
        has_noobs?: has_noobs?,
        invalid_match?: false
      }
    end
  end

  # Teams are a list of players
  # First team is always the winning team
  # Returns the forecast error squared
  defp process_sql_result(teams, rating_system) do
    openskill_teams =
      teams |> Enum.map(fn {x, v} -> convert_player_list_to_tuple_list(v, rating_system) end)

    # When predicting, we should feed into the openskill library the {skill, uncertainty} of players
    # However, since we balance on player rating, instead we feed in {rating, uncertainty} of all players

    [team1_win_predict, _team2_win_predict] = Openskill.predict_win(openskill_teams)
    # team 1 is the winning team
    get_forecast_error_squared(team1_win_predict)
  end

  # Fully accurate forecast will be 0.
  # Lower is better
  defp get_forecast_error_squared(winning_team_predict) do
    (winning_team_predict - 1) ** 2
  end

  # Converts a list of player maps into tuples to be fed into OpenSkill library win_predict function
  defp convert_player_list_to_tuple_list(player_list, rating_system) do
    player_list |> Enum.map(fn x -> {get_rating(x, rating_system), x.uncertainty} end)
  end

  defp get_rating(player, rating_system) do
    case rating_system do
      :openskill -> player.skill
      :bar -> max(player.skill - player.uncertainty, 0)
      :provisional -> min(player.num_matches / @provisional_num_matches_cutoff, 1) * player.skill
    end
  end
end
