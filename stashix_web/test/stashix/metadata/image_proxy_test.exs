defmodule Stashix.Metadata.ImageProxyTest do
  use Stashix.DataCase, async: false

  alias Stashix.Metadata.{HTTP, ImageProxy}

  @url "https://comicvine.gamespot.com/a/uploads/scale_small/1/100/1-cover.jpg"

  setup do
    dir = Path.join(System.tmp_dir!(), "stashix-image-proxy-#{System.unique_integer([:positive])}")
    previous = Application.get_env(:stashix, :metadata_image_dir)
    Application.put_env(:stashix, :metadata_image_dir, dir)

    on_exit(fn ->
      Application.put_env(:stashix, :metadata_image_dir, previous)
      File.rm_rf(dir)
    end)

    %{dir: dir}
  end

  defp stub_image(counter, type \\ "image/jpeg") do
    Req.Test.stub(HTTP, fn conn ->
      Agent.update(counter, &(&1 + 1))
      conn |> Plug.Conn.put_resp_content_type(type, nil) |> Plug.Conn.send_resp(200, "imagebytes")
    end)
  end

  test "only source image hosts are allowed" do
    assert ImageProxy.allowed?(@url)
    assert ImageProxy.allowed?("https://static.metron.cloud/media/issue/cover.jpg")
    assert ImageProxy.allowed?("https://files1.comics.org/img/gcd/covers_by_id/1/w100/1.jpg")
    refute ImageProxy.allowed?("https://evil.example.com/cover.jpg")
    refute ImageProxy.allowed?("https://comicvine.gamespot.com.evil.com/cover.jpg")
    refute ImageProxy.allowed?("file:///etc/passwd")
    refute ImageProxy.allowed?(nil)
    assert ImageProxy.fetch("http://localhost:4000/admin") == {:error, :forbidden}
  end

  test "downloads once and serves later requests from disk", %{dir: dir} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    stub_image(counter)

    assert {:file, path, "image/jpeg"} = ImageProxy.fetch(@url)
    assert Path.dirname(path) == dir
    assert File.read!(path) == "imagebytes"
    assert {:file, ^path, "image/jpeg"} = ImageProxy.fetch(@url)
    assert Agent.get(counter, & &1) == 1

    assert ImageProxy.clear() == 1
    refute File.exists?(path)
  end

  test "rejects non-raster content types" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    stub_image(counter, "image/svg+xml")
    assert ImageProxy.fetch(@url) == {:error, :unsupported_type}
  end

  test "does not follow redirects to other hosts" do
    Req.Test.stub(HTTP, fn conn ->
      conn |> Plug.Conn.put_resp_header("location", "http://169.254.169.254/latest") |> Plug.Conn.send_resp(302, "")
    end)

    assert ImageProxy.fetch(@url) == {:error, :forbidden}
  end
end
