defmodule ChessEnabledWeb.MatchChannel do
  use Phoenix.Channel

  alias ChessEnabled.Accounts
  alias ChessEnabled.Matches

  alias ChessEnabledWeb.FallbackController
  alias ChessEnabledWeb.Endpoint

  # anybody can join and spectate, so each push needs auth
  def join("match:" <> id, _, socket) do
    {:ok, %{status: true}, socket}
  end

  def handle_in("get_match", _, socket) do
    try do
      match_id = socket.topic
                 |> String.split(":", trim: true)
                 |> Enum.at(1)
      {:ok, {:ok, match_idx, match}} = Matches.get_match(match_id)
      {:reply, {:ok, %{idx: match_idx, match: match}}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:reply, {:error, FallbackController.call(nil, {:error, err})}, socket}
    end
  end

  def handle_in("send_move", %{"token" => token, "id" => piece_id, "to_r" => to_r, "to_c" => to_c}, socket) do
    try do
      {:ok, user_id} = Accounts.auth_user_token!([token])
      match_id = socket.topic
                 |> String.split(":", trim: true)
                 |> Enum.at(1)
      {:ok, {:ok, match_idx, time_spent, running, from_r, from_c, to_r, to_c, closed, users}} = Matches.send_move!(user_id, match_id, piece_id, to_r, to_c)
      if closed do
        users
        |> Enum.each(fn ({user_id, user_idx}) ->
          Endpoint.broadcast!("matches:" <> user_id, "match_closed", %{idx: user_idx, match_id: match_id})
        end)
        broadcast!(socket, "match_closed_with_move", %{idx: match_idx, move: %{user_id: user_id, time_spent: time_spent, running: running, from_r: from_r, from_c: from_c, to_r: to_r, to_c: to_c}})
      else
        broadcast!(socket, "sent_move", %{idx: match_idx, move: %{user_id: user_id, time_spent: time_spent, running: running, from_r: from_r, from_c: from_c, to_r: to_r, to_c: to_c}})
      end
      {:reply, {:ok, %{status: true}}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:reply, {:error, FallbackController.call(nil, {:error, err})}, socket}
    end
  end

  # must be done within 30 seconds
  def handle_in("accept_match", %{"token" => token}, socket) do
    try do
      {:ok, user_id} = Accounts.auth_user_token!([token])
      match_id = socket.topic
                 |> String.split(":", trim: true)
                 |> Enum.at(1)
      {:ok, {:ok, match_idx, open}} = Matches.accept_match!(user_id, match_id)
      if open do
        broadcast!(socket, "match_open", %{idx: match_idx})
      else
        broadcast!(socket, "match_accepted", %{idx: match_idx, user_id: user_id})
      end
      {:reply, {:ok, %{status: true}}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:reply, {:error, FallbackController.call(nil, {:error, err})}, socket}
    end
  end

  def handle_in("clear_match", %{"token" => token}, socket) do
    try do
      match_id = socket.topic
                 |> String.split(":", trim: true)
                 |> Enum.at(1)
      {:ok, {:ok, users, match_id}} = Matches.clear_match!(match_id)
      users
      |> Enum.each(fn ({user_id, user_idx}) ->
        Endpoint.broadcast!("matches:" <> user_id, "match_cleared", %{idx: user_idx, match_id: match_id})
      end)
      {:reply, {:ok, %{status: true}}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:reply, {:error, FallbackController.call(nil, {:error, err})}, socket}
    end
  end

  def handle_in("close_match", _, socket) do
    try do
      match_id = socket.topic
                 |> String.split(":", trim: true)
                 |> Enum.at(1)
      {:ok, {:ok, match_idx, users}} = Matches.close_match!(match_id)
      users
      |> Enum.each(fn ({user_id, user_idx}) ->
        Endpoint.broadcast!("matches:" <> user_id, "match_closed", %{idx: user_idx, match_id: match_id})
      end)
      broadcast!(socket, "match_closed", %{idx: match_idx})
      {:reply, {:ok, %{status: true}}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:reply, {:error, FallbackController.call(nil, {:error, err})}, socket}
    end
  end
end
