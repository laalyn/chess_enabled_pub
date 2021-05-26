defmodule ChessEnabled.Accounts do
  import Ecto.Query, warn: false
  alias ChessEnabled.Repo
  alias ChessEnabled.Guardian

  alias ChessEnabled.Accounts.User

  def auth_user_token!(token) do
    with {:ok, claims} <- token
                          |> Enum.at(0)
                          |> String.split(" ", trim: true)
                          |> Enum.at(1)
                          |> Guardian.decode_and_verify do
      # check if user exists
      user_query = from u in User,
                     where: u.id == ^claims["sub"]
      with true <- user_query
                   |> Repo.exists? do
        {:ok, claims["sub"]}
      else _ ->
        raise "user doesn't exist"
      end
    else _ ->
      raise "not authorized"
    end
  end

  def auth_user_local!(attrs \\ %{}) do
    with {:ok, %User{} = user} <- User
                                  |> Repo.get_by(email: attrs["email"])
                                  |> Argon2.check_pass(attrs["password"]) do
      Guardian.encode_and_sign(user)
    else _ ->
      raise "authentication failed"
    end
  end

  def create_user!(attrs \\ %{}) do
    Repo.transaction(fn ->
      user = %User {
        next_idx: 0,
      }
      |> User.changeset(attrs)
      |> Repo.insert!

      {:ok, user.id}
    end)
  end
end