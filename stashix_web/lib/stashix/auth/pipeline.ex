defmodule Stashix.Auth.Pipeline do
  use Guardian.Plug.Pipeline,
    otp_app: :stashix,
    module: Stashix.Auth.Guardian,
    error_handler: Stashix.Auth.ErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.LoadResource, allow_blank: true
end
