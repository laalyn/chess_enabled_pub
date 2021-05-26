defmodule ChessEnabledWeb.QueueController do
  use ChessEnabledWeb, :controller

  alias ChessEnabled.Accounts
  alias ChessEnabled.Queue

  alias Plug.Conn

  alias ChessEnabledWeb.FallbackController

  action_fallback ChessEnabledWeb.FallbackController

  def list(conn, _) do
    try do
      {:ok, user_id} = conn
                       |> Conn.get_req_header("authorization")
                       |> Accounts.auth_user_token!
      {:ok, {:ok, idx, queued}} = Queue.list_queued(user_id)
      conn
      |> put_status(:ok)
      |> json(%{idx: idx, queued: queued})
    rescue err ->
      IO.inspect(__STACKTRACE__)
      FallbackController.call(conn, {:error, err})
    end
  end
end
