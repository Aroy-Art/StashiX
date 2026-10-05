defmodule Stashix.Auth.Guardian do
  use Guardian, otp_app: :stashix

  alias Stashix.Accounts

  def subject_for_token(user, _claims) do
    {:ok, to_string(user.id)}
  end

  def build_claims(claims, user, _opts) do
    {:ok, Map.put(claims, "ver", user.token_version)}
  end

  # Tokens issued before the user's password or role last changed carry an
  # older "ver" and are rejected.
  def resource_from_claims(%{"sub" => id} = claims) do
    case Accounts.get_user(id) do
      nil -> {:error, :resource_not_found}
      user -> if user.token_version == claims["ver"], do: {:ok, user}, else: {:error, :token_revoked}
    end
  end
end
