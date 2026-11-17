# SPDX-FileCopyrightText: 2026 Aroy <me@aroy-art.com> & Contributors
# SPDX-License-Identifier: AGPL-3.0-or-later

defmodule StashixWeb.Plugs.ReaderCSP do
  @moduledoc """
  Content Security Policy for the text reader, which shows book content
  (EPUB HTML) in `blob:` iframes that run as this page and inherit its CSP.
  The iframes can't be sandboxed against scripts (foliate-js needs
  `allow-scripts` for WebKit), so this policy is what keeps a book's
  `<script>` from running: only our own files and the inline scripts of the
  root layout, which carry a per-request nonce (`@conn.assigns.csp_nonce`).

  The reader lives in its own `live_session`, so it is always a fresh page
  load with this header, never a live navigation from a page without it.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    nonce = 18 |> :crypto.strong_rand_bytes() |> Base.encode64()

    conn
    |> assign(:csp_nonce, nonce)
    |> put_resp_header("content-security-policy", policy(nonce))
  end

  # wasm-unsafe-eval: PDF.js decodes JPEG 2000 and JBIG2 images in wasm.
  # blob: is where the book's own documents, styles, fonts and pictures load.
  defp policy(nonce) do
    Enum.join(
      [
        "default-src 'self'",
        "script-src 'self' 'nonce-#{nonce}' 'wasm-unsafe-eval'",
        "style-src 'self' 'unsafe-inline' blob:",
        "img-src 'self' data: blob:",
        "font-src 'self' data: blob:",
        "media-src 'self' blob:",
        "connect-src 'self'",
        "worker-src 'self' blob:",
        "frame-src 'self' blob:",
        "object-src 'none'",
        "form-action 'self'",
        "base-uri 'self'",
        "frame-ancestors 'self'"
      ],
      "; "
    )
  end
end
