defmodule ChessEnabledWeb.FallbackController do
  use ChessEnabledWeb, :controller

  def call(conn, err) do
    IO.inspect(err)
    disp = case elem(err, 1) do
      {:error, %Ecto.Changeset{} = chg} ->
        chg.errors
        |> hd
        |> elem(1)
        |> elem(0)
      %Ecto.InvalidChangesetError{} = chg_err ->
        chg_err.changeset.errors
        |> hd
        |> elem(1)
        |> elem(0)
      %RuntimeError{} = re ->
        re.message
      str ->
        if String.valid?(str) do
          str
        else
          "something went wrong"
        end
    end
    if conn do
      conn
      |> put_status(:bad_request)
      |> json(%{error: disp})
    else
      %{reason: disp}
    end
  end
end
