defmodule ChessEnabledWeb.QueueChannel do
  use Phoenix.Channel

  alias ChessEnabled.Accounts
  alias ChessEnabled.Queue

  alias ChessEnabledWeb.FallbackController
  alias ChessEnabledWeb.Endpoint

  def join("queue:" <> id, %{"token" => token}, socket) do
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

  def handle_in("list_queued", _, socket) do
    try do
      user_id = socket.topic
                |> String.split(":", trim: true)
                |> Enum.at(1)
      {:ok, {:ok, idx, queued}} = Queue.list_queued(user_id)
      # idx is returned here because the user needs the base idx
      {:reply, {:ok, %{idx: idx, queued: queued}}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:reply, {:error, FallbackController.call(nil, {:error, err})}, socket}
    end
  end

  def handle_in("join_queue", %{"type" => type}, socket) do
    try do
      user_id = socket.topic
                |> String.split(":", trim: true)
                |> Enum.at(1)
      {:ok, {:ok, users, match}} = Queue.join_queue!(user_id, type)
      if match !== nil do
        users
        |> Enum.each(fn ({id, idx}) ->
          Endpoint.broadcast!("queue:" <> id, "match_pending", %{idx: idx, match: match})
        end)
      else
        broadcast!(socket, "joined_queue", %{idx: hd users})
      end
      {:reply, {:ok, %{status: true}}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:reply, {:error, FallbackController.call(nil, {:error, err})}, socket}
    end
  end

  def handle_in("leave_queue", %{"type" => type}, socket) do
    try do
      user_id = socket.topic
                |> String.split(":", trim: true)
                |> Enum.at(1)
      {:ok, {:ok, users}} = Queue.leave_queue!(user_id, type)
      broadcast!(socket, "left_queue", %{idx: hd users})
      {:reply, {:ok, %{status: true}}, socket}
    rescue err ->
      IO.inspect(__STACKTRACE__)
      {:reply, {:error, FallbackController.call(nil, {:error, err})}, socket}
    end
  end
end
