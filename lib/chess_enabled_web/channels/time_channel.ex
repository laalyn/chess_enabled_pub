defmodule ChessEnabledWeb.TimeChannel do
  use Phoenix.Channel

  alias ChessEnabled.Accounts

  alias ChessEnabledWeb.FallbackController
  alias ChessEnabledWeb.Endpoint

  def join("time:lobby", _, socket) do
    {:ok, %{status: true}, socket}
  end

  # TODO actually use ntp
  def handle_in("cur_time", _, socket) do
    {:reply, {:ok, %{timestamp: DateTime.utc_now}}, socket}
  end
end