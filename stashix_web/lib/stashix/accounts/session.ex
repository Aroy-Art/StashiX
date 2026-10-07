defmodule Stashix.Accounts.Session do
  @moduledoc """
  One sign-in of a user: a browser, or an app using the API. Kept so the user
  can see where their account is open and close one of them: tokens name
  their session, and stop working once its row is gone.

  A row counts as live while it has not expired and its `token_version` still
  matches the user's, so bumping that version retires every session at once
  without touching this table.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_sessions" do
    field :user_agent, :string
    field :ip_address, :string
    field :token_version, :integer
    field :last_seen_at, :utc_datetime
    field :expires_at, :utc_datetime

    belongs_to :user, Stashix.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc ~S'A short name for the client, e.g. "Firefox on Linux", read from its user agent.'
  def device(%__MODULE__{user_agent: user_agent}) when is_binary(user_agent) and user_agent != "" do
    case {browser(user_agent), os(user_agent)} do
      {nil, nil} -> user_agent |> String.split(" ", parts: 2) |> hd()
      {browser, nil} -> browser
      {nil, os} -> os
      {browser, os} -> "#{browser} on #{os}"
    end
  end

  def device(%__MODULE__{}), do: "Unknown device"

  # Order matters: Edge and Opera also say "Chrome", and Chrome says "Safari".
  defp browser(user_agent) do
    cond do
      user_agent =~ ~r{Edg(e|A|iOS)?/} -> "Edge"
      user_agent =~ "OPR/" -> "Opera"
      user_agent =~ ~r{(Firefox|FxiOS)/} -> "Firefox"
      user_agent =~ ~r{(Chrome|CriOS)/} -> "Chrome"
      user_agent =~ "Safari/" -> "Safari"
      true -> nil
    end
  end

  # Android says "Linux" and iOS says "like Mac OS X", so those come first.
  defp os(user_agent) do
    cond do
      user_agent =~ "Android" -> "Android"
      user_agent =~ "iPhone" -> "iPhone"
      user_agent =~ "iPad" -> "iPad"
      user_agent =~ "Windows" -> "Windows"
      user_agent =~ "Mac OS X" -> "macOS"
      user_agent =~ "CrOS" -> "ChromeOS"
      user_agent =~ "Linux" -> "Linux"
      true -> nil
    end
  end
end
