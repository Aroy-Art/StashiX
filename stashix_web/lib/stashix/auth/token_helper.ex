defmodule Stashix.Auth.TokenHelper do
  alias Stashix.Accounts
  alias Stashix.Auth.Guardian

  @doc """
  An access and a refresh token for the user. `session_id` is carried as the
  "sid" claim, so a refresh can be traced back to the sign-in it belongs to.
  """
  def generate_tokens(user, session_id \\ nil) do
    claims = if session_id, do: %{"sid" => session_id}, else: %{}

    with {:ok, access_token, _claims} <-
           Guardian.encode_and_sign(user, claims, token_type: "access", ttl: {15, :minutes}),
         {:ok, refresh_token, _claims} <-
           Guardian.encode_and_sign(user, claims, token_type: "refresh", ttl: {7, :days}) do
      {:ok, access_token, refresh_token}
    end
  end

  @doc "Records a sign-in (see `Accounts.create_session/2`) and issues its tokens."
  def start_session(user, user_agent) do
    with {:ok, session} <- Accounts.create_session(user, user_agent),
         {:ok, access_token, refresh_token} <- generate_tokens(user, session.id) do
      {:ok, access_token, refresh_token, session.id}
    end
  end

  def verify_refresh_token(token) do
    Guardian.decode_and_verify(token, %{"typ" => "refresh"})
  end

  @doc "User for an access token; refresh tokens are rejected."
  def resource_from_token(token) do
    with {:ok, claims} <- Guardian.decode_and_verify(token, %{"typ" => "access"}),
         {:ok, user} <- Guardian.resource_from_claims(claims) do
      {:ok, user}
    end
  end

  @doc """
  The user a browser session belongs to: by its access token, or failing that
  its refresh token. `session` is the session map with string keys.
  """
  def user_from_session(session) do
    access_token = session["guardian_default_token"]

    case access_token && resource_from_token(access_token) do
      {:ok, user} ->
        {:ok, user}

      _ ->
        refresh_token = session["guardian_refresh_token"]

        case refresh_token && refresh_tokens(refresh_token) do
          {:ok, user, _new_access, _new_refresh} -> {:ok, user}
          _ -> {:error, :unauthenticated}
        end
    end
  end

  def refresh_tokens(refresh_token) do
    with {:ok, claims} <- Guardian.decode_and_verify(refresh_token, %{"typ" => "refresh"}),
         {:ok, user} <- Guardian.resource_from_claims(claims),
         {:ok, access_token, new_refresh_token} <- generate_tokens(user, claims["sid"]) do
      {:ok, user, access_token, new_refresh_token}
    end
  end
end
