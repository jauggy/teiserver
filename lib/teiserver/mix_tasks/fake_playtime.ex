defmodule Mix.Tasks.Teiserver.FakePlaytime do
  @moduledoc """
  Adds fake play time stats to all non bot users
  Run with
  mix teiserver.fake_playtime
  """

  use Mix.Task
  require Logger
  alias Teiserver.{Account, CacheUser}

  def run(_args) do
    Application.ensure_all_started(:teiserver)

    if Application.get_env(:teiserver, Teiserver)[:enable_hailstorm] do
      Account.list_users(
        search: [
          not_has_role: "Bot"
        ],
        select: [:id, :name]
      )
      |> Enum.map(fn user ->
        update_stats(user.id, random_playtime())
      end)

      Logger.info("Finished applying fake playtime data")
    end
  end

  def update_stats(user_id, player_minutes) do
    Account.update_user_stat(user_id, %{
      player_minutes: player_minutes,
      total_minutes: player_minutes
    })

    # Now recalculate ranks
    # This calc would usually be done in do_login
    rank = CacheUser.calculate_rank(user_id)
    user = Teiserver.Account.UserCacheLib.get_user_by_id(user_id)

    user = %{
      user
      | rank: rank
    }

    CacheUser.update_user(user, true)
  end

  defp random_playtime() do
    hours =
      case get_player_experience() do
        :just_installed -> Enum.random(0..4)
        :noob -> Enum.random(5..99)
        :average -> Enum.random(100..249)
        :pro -> Enum.random(250..1750)
      end

    hours * 60
  end

  @spec get_player_experience() :: :just_installed | :noob | :average | :pro
  defp get_player_experience do
    case Enum.random(0..3) do
      0 -> :just_installed
      1 -> :noob
      2 -> :average
      3 -> :pro
    end
  end
end
