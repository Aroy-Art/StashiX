defmodule StashixWeb.LibraryChannel do
  use StashixWeb, :channel

  alias Stashix.{Accounts, Library}
  alias Stashix.Library.Access

  @impl true
  def join("library:" <> user_id, _params, socket) do
    if socket.assigns.user_id == user_id do
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_in("update_progress", %{"book_id" => book_id, "page" => page}, socket) do
    user_id = socket.assigns.user_id
    access = Access.for_user(Accounts.get_user(user_id))

    case Library.update_progress(access, user_id, book_id, page) do
      {:ok, _} ->
        {:reply, {:ok, %{page: page}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  def handle_in(_event, _payload, socket) do
    {:noreply, socket}
  end
end
