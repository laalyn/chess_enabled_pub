defmodule ChessEnabledWeb.UserController do
  use ChessEnabledWeb, :controller

  alias ChessEnabled.Accounts

  alias Plug.Conn

  alias ChessEnabledWeb.FallbackController

  action_fallback ChessEnabledWeb.FallbackController

  def cur(conn, _) do
    try do
      {:ok, user_id} = conn
                       |> Conn.get_req_header("authorization")
                       |> Accounts.auth_user_token!
      conn
      |> put_status(:ok)
      |> json(%{user_id: user_id})
    rescue err ->
      IO.inspect(__STACKTRACE__)
      FallbackController.call(conn, {:error, err})
    end
  end

  def auth(conn, %{"local" => local}) do
    try do
      {:ok, token, _claims} = Accounts.auth_user_local!(local)
      conn
      |> put_status(:ok)
      |> json(%{token: token})
    rescue err ->
      IO.inspect(__STACKTRACE__)
      FallbackController.call(conn, {:error, err})
    end
  end

  def create(conn, %{"user" => user}) do
    try do
      {:ok, {:ok, _user_id}} = Accounts.create_user!(user)
      conn
      |> put_status(:created)
      |> json(%{status: true})
    rescue err ->
      IO.inspect(__STACKTRACE__)
      FallbackController.call(conn, {:error, err})
    end
  end
end
