defmodule Stashix.Metadata.HTTP.Error do
  defexception [:reason]

  @impl true
  def message(%{reason: reason}), do: Stashix.Metadata.HTTP.error_message(reason)
end
