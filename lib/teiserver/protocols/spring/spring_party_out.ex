defmodule Teiserver.Protocols.Spring.PartyOut do
  require Logger

  def do_reply(:invited_to_party, party_id, state) do
    "s.party.invited_to_party #{party_id} #{state.user.name}\n"
  end

  def do_reply(event, data, _state) do
    Logger.error("No handler for event `#{event}` with data #{inspect(data)}")
    "\n"
  end
end
