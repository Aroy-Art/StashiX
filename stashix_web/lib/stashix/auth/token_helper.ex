defmodule Stashix.Auth.TokenHelper do
  alias Stashix.Auth.Guardian

  def generate_tokens(user) do
    with {:ok, access_token, _claims} <-
           Guardian.encode_and_sign(user, %{}, token_type: "access", ttl: {15, :minutes}),
         {:ok, refresh_token, _claims} <-
           Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: {7, :days}) do
      {:ok, access_token, refresh_token}
    end
  end

  def verify_refresh_token(token) do
    Guardian.decode_and_verify(token, %{"typ" => "refresh"})
  end

  def resource_from_token(token) do
    with {:ok, claims} <- Guardian.decode_and_verify(token),
         {:ok, user} <- Guardian.resource_from_claims(claims) do
      {:ok, user}
    end
  end
end
