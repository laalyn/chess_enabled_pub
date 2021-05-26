defmodule ChessEnabledWeb.MatchesChannel do
  use Phoenix.Channel

  alias ChessEnabled.Accounts
  alias ChessEnabled.Queue
  alias ChessEnabled.Matches

  alias ChessEnabledWeb.FallbackController
  alias ChessEnabledWeb.Endpoint

  def join("matches:" <> id, %{"token" => token}, socket) do
    try do
      {:ok, user_id} = Accounts.auth_user_token!([token])
      if user_id !== id do
        raise "room forbidden"
      end
      {:ok, %{status: true}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:error, FallbackController.call(nil, {:error, err})}
    end
  end

  def handle_in("list_matches", _, socket) do
    try do
      user_id = socket.topic
                |> String.split(":", trim: true)
                |> Enum.at(1)
      {:ok, {:ok, idx, matches}} = Matches.list_matches(user_id)
      {:reply, {:ok, %{idx: idx, matches: matches}}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:reply, {:error, FallbackController.call(nil, {:error, err})}, socket}
    end
  end
end
