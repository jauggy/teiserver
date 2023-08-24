defmodule Teiserver.Account.RelationshipLib do
  @moduledoc false
  alias Teiserver.Account
  alias Teiserver.Data.Types, as: T

  @spec colour :: atom
  def colour(), do: :success

  @spec icon :: String.t()
  def icon(), do: "fa-users"

  @spec icon_follow :: String.t()
  def icon_follow(), do: "fa-eyes"

  @spec icon_ignore :: String.t()
  def icon_ignore(), do: "fa-volume-slash"

  @spec icon_avoid :: String.t()
  def icon_avoid(), do: "fa-ban"

  @spec icon_block :: String.t()
  def icon_block(), do: "fa-octagon-exclamation"

  @spec verb_of_state(String.t | map) :: String.t
  def verb_of_state("follow"), do: "following"
  def verb_of_state("ignore"), do: "ignoring"
  def verb_of_state("avoid"), do: "avoiding"
  def verb_of_state("block"), do: "blocking"
  def verb_of_state(nil), do: ""
  def verb_of_state(%{state: state}), do: verb_of_state(state)

  @spec past_tense_of_state(String.t | map) :: String.t
  def past_tense_of_state("follow"), do: "followed"
  def past_tense_of_state("ignore"), do: "ignored"
  def past_tense_of_state("avoid"), do: "avoided"
  def past_tense_of_state("block"), do: "blocked"
  def past_tense_of_state(nil), do: ""
  def past_tense_of_state(%{state: state}), do: past_tense_of_state(state)

  @spec follow_user(T.userid, T.userid) :: {:ok, Account.Relationship.t}
  def follow_user(from_user_id, to_user_id) when is_integer(from_user_id) and is_integer(to_user_id) do
    Account.upsert_relationship(%{
      from_user_id: from_user_id,
      to_user_id: to_user_id,
      state: "follow"
    })
  end

  @spec ignore_user(T.userid, T.userid) :: {:ok, Account.Relationship.t}
  def ignore_user(from_user_id, to_user_id) when is_integer(from_user_id) and is_integer(to_user_id) do
    Account.upsert_relationship(%{
      from_user_id: from_user_id,
      to_user_id: to_user_id,
      state: "ignore"
    })
  end

  @spec avoid_user(T.userid, T.userid) :: {:ok, Account.Relationship.t}
  def avoid_user(from_user_id, to_user_id) when is_integer(from_user_id) and is_integer(to_user_id) do
    Account.upsert_relationship(%{
      from_user_id: from_user_id,
      to_user_id: to_user_id,
      state: "avoid"
    })
  end

  @spec block_user(T.userid, T.userid) :: {:ok, Account.Relationship.t}
  def block_user(from_user_id, to_user_id) when is_integer(from_user_id) and is_integer(to_user_id) do
    Account.upsert_relationship(%{
      from_user_id: from_user_id,
      to_user_id: to_user_id,
      state: "block"
    })
  end

  @spec reset_relationship_state(T.userid, T.userid) :: {:ok, Account.Relationship.t}
  def reset_relationship_state(from_user_id, to_user_id) when is_integer(from_user_id) and is_integer(to_user_id) do
    Account.upsert_relationship(%{
      from_user_id: from_user_id,
      to_user_id: to_user_id,
      state: nil
    })
  end

  @spec calculate_relationship_stats(T.userid) :: :ok
  def calculate_relationship_stats(userid) do
    data = %{
      follower_count: 0,
      following_count: 0,

      ignoring_count: 0,
      ignored_count: 0,

      avoiding_count: 0,
      avoided_count: 0,

      blocking_count: 0,
      blocked_count: 0,
    }


    Account.update_user_stat(userid, data)

    :ok
  end

  @spec decache_relationships(T.userid) :: :ok
  def decache_relationships(userid) do
    Central.cache_delete(:account_follow_cache, userid)
    Central.cache_delete(:account_avoid_cache, userid)
    Central.cache_delete(:account_ignore_cache, userid)
    Central.cache_delete(:account_block_cache, userid)
    :ok
  end

  @spec list_userids_followed_by_userid(T.userid) :: [T.userid]
  def list_userids_followed_by_userid(userid) do
    Central.cache_get_or_store(:account_follow_cache, userid, fn ->
      Account.list_relationships(
        where: [
          from_user_id: userid,
          state: "follow",
        ],
        select: [:to_user_id]
      )
      |> Enum.map(fn r ->
        r.to_user_id
      end)
    end)
  end

  @spec list_userids_avoiding_this_userid(T.userid) :: [T.userid]
  def list_userids_avoiding_this_userid(userid) do
    Central.cache_get_or_store(:account_avoiding_this_cache, userid, fn ->
      Account.list_relationships(
        where: [
          to_user_id: userid,
          state: "avoid",
        ],
        select: [:from_user_id]
      )
      |> Enum.map(fn r ->
        r.from_user_id
      end)
    end)
  end

  @spec list_userids_avoided_by_userid(T.userid) :: [T.userid]
  def list_userids_avoided_by_userid(userid) do
    Central.cache_get_or_store(:account_avoid_cache, userid, fn ->
      Account.list_relationships(
        where: [
          from_user_id: userid,
          state: "avoid",
        ],
        select: [:to_user_id]
      )
      |> Enum.map(fn r ->
        r.to_user_id
      end)
    end)
  end

  @spec list_userids_blocked_by_userid(T.userid) :: [T.userid]
  def list_userids_blocked_by_userid(userid) do
    Central.cache_get_or_store(:account_block_cache, userid, fn ->
      Account.list_relationships(
        where: [
          from_user_id: userid,
          state: "block",
        ],
        select: [:to_user_id]
      )
      |> Enum.map(fn r ->
        r.to_user_id
      end)
    end)
  end

  @spec list_userids_ignored_by_userid(T.userid) :: [T.userid]
  def list_userids_ignored_by_userid(userid) do
    Central.cache_get_or_store(:account_ignore_cache, userid, fn ->
      Account.list_relationships(
        where: [
          from_user_id: userid,
          state: "ignore",
        ],
        select: [:to_user_id]
      )
      |> Enum.map(fn r ->
        r.to_user_id
      end)
    end)
  end

  @spec does_a_follow_b?(T.userid, T.userid) :: boolean
  def does_a_follow_b?(u1, u2) do
    Enum.member?(list_userids_followed_by_userid(u1), u2)
  end

  @spec does_a_ignore_b?(T.userid, T.userid) :: boolean
  def does_a_ignore_b?(u1, u2) do
    Enum.member?(list_userids_ignored_by_userid(u1), u2)
    or does_a_avoid_b?(u1, u2)
  end

  @spec does_a_avoid_b?(T.userid, T.userid) :: boolean
  def does_a_avoid_b?(u1, u2) do
    Enum.member?(list_userids_avoided_by_userid(u1), u2)
    or does_a_block_b?(u1, u2)
  end

  @spec does_a_block_b?(T.userid, T.userid) :: boolean
  def does_a_block_b?(u1, u2) do
    Enum.member?(list_userids_blocked_by_userid(u1), u2)
  end
end