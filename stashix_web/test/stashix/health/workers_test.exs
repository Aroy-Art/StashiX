defmodule Stashix.Health.WorkersTest do
  use Stashix.DataCase, async: false
  use Oban.Testing, repo: Stashix.Repo

  alias Stashix.{Health, Library, Repo}
  alias Stashix.Health.CheckResult
  alias Stashix.Health.Workers.{IntegrityFileWorker, IntegrityLibraryWorker}
  alias Stashix.Library.{Book, BookFile}

  setup do
    tmp = Path.join(System.tmp_dir!(), "stashix_health_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, lib} = Library.create_library(%{name: "Health Test Lib", root_path: tmp})
    {:ok, %{tmp: tmp, lib: lib}}
  end

  # ── IntegrityFileWorker ───────────────────────────────────────────────────

  describe "IntegrityFileWorker" do
    test "saves :ok result and broadcasts for a valid CBZ", %{tmp: tmp, lib: lib} do
      path = write_cbz(tmp, "good.cbz")
      {book, bf} = insert_book_file(lib, path)

      Phoenix.PubSub.subscribe(Stashix.PubSub, "health:#{lib.id}")

      assert :ok =
               perform_job(IntegrityFileWorker, %{"book_file_id" => bf.id, "library_id" => lib.id})

      result = Repo.get_by!(CheckResult, book_file_id: bf.id, check_type: :integrity)
      assert result.status == :ok
      assert result.error_message == nil

      assert_receive {:integrity_file_done, %{library_id: lib_id, status: :ok}}
      assert lib_id == lib.id
    end

    test "saves :error and broadcasts for a corrupt CBZ", %{tmp: tmp, lib: lib} do
      path = Path.join(tmp, "corrupt.cbz")
      File.write!(path, "this is not a zip file at all")
      {_book, bf} = insert_book_file(lib, path)

      Phoenix.PubSub.subscribe(Stashix.PubSub, "health:#{lib.id}")

      assert :ok =
               perform_job(IntegrityFileWorker, %{"book_file_id" => bf.id, "library_id" => lib.id})

      result = Repo.get_by!(CheckResult, book_file_id: bf.id, check_type: :integrity)
      assert result.status == :error
      assert result.error_message != nil

      assert_receive {:integrity_file_done, %{status: :error}}
    end

    test "saves :error and broadcasts when file is missing from disk", %{tmp: tmp, lib: lib} do
      path = Path.join(tmp, "ghost.cbz")
      {_book, bf} = insert_book_file(lib, path)

      Phoenix.PubSub.subscribe(Stashix.PubSub, "health:#{lib.id}")

      assert :ok =
               perform_job(IntegrityFileWorker, %{"book_file_id" => bf.id, "library_id" => lib.id})

      result = Repo.get_by!(CheckResult, book_file_id: bf.id, check_type: :integrity)
      assert result.status == :error
      assert result.error_message == "File not found on disk"

      assert_receive {:integrity_file_done, %{status: :error}}
    end

    test "cancels gracefully when book_file does not exist in DB", %{lib: lib} do
      phantom_id = Ecto.UUID.generate()

      assert {:cancel, :not_found} =
               perform_job(IntegrityFileWorker, %{
                 "book_file_id" => phantom_id,
                 "library_id" => lib.id
               })
    end

    test "upserts result on re-check (no duplicate rows)", %{tmp: tmp, lib: lib} do
      path = write_cbz(tmp, "recheck.cbz")
      {_book, bf} = insert_book_file(lib, path)

      perform_job(IntegrityFileWorker, %{"book_file_id" => bf.id, "library_id" => lib.id})
      perform_job(IntegrityFileWorker, %{"book_file_id" => bf.id, "library_id" => lib.id})

      count =
        Repo.aggregate(
          from(r in CheckResult,
            where: r.book_file_id == ^bf.id and r.check_type == :integrity
          ),
          :count
        )

      assert count == 1
    end
  end

  # ── IntegrityLibraryWorker ────────────────────────────────────────────────

  describe "IntegrityLibraryWorker" do
    test "enqueues one IntegrityFileWorker per active book_file and broadcasts total",
         %{tmp: tmp, lib: lib} do
      for name <- ~w(a.cbz b.cbz c.cbz) do
        path = write_cbz(tmp, name)
        insert_book_file(lib, path)
      end

      Phoenix.PubSub.subscribe(Stashix.PubSub, "health:#{lib.id}")

      assert :ok = perform_job(IntegrityLibraryWorker, %{"library_id" => lib.id})

      assert_enqueued(worker: IntegrityFileWorker, args: %{library_id: lib.id})

      enqueued =
        all_enqueued(worker: IntegrityFileWorker)
        |> Enum.filter(&(&1.args["library_id"] == lib.id))

      assert length(enqueued) == 3

      assert_receive {:integrity_started, %{library_id: lib_id, total: 3}}
      assert lib_id == lib.id
    end

    test "clears old results before enqueuing", %{tmp: tmp, lib: lib} do
      path = write_cbz(tmp, "old.cbz")
      {_book, bf} = insert_book_file(lib, path)

      Repo.insert!(%CheckResult{
        library_id: lib.id,
        book_file_id: bf.id,
        check_type: :integrity,
        file_path: path,
        status: :error,
        error_message: "stale",
        checked_at: ~N[2020-01-01 00:00:00]
      })

      assert :ok = perform_job(IntegrityLibraryWorker, %{"library_id" => lib.id})

      remaining = Repo.all(from r in CheckResult, where: r.library_id == ^lib.id and r.check_type == :integrity)
      assert remaining == []
    end
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp write_cbz(dir, filename) do
    path = Path.join(dir, filename)
    files = [{'page001.jpg', "fake jpeg content"}]
    {:ok, {_, data}} = :zip.create(String.to_charlist(path), files, [:memory])
    File.write!(path, data)
    path
  end

  defp insert_book_file(lib, path) do
    {:ok, book} =
      Library.create_book(%{
        library_id: lib.id,
        title: Path.basename(path, Path.extname(path)),
        type: "standalone",
        page_count: 1
      })

    ext = path |> Path.extname() |> String.downcase() |> String.trim_leading(".") |> String.to_atom()
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    {:ok, bf} =
      Library.create_book_file(%{
        book_id: book.id,
        path: path,
        format: ext,
        file_size: 100,
        file_hash: "test:#{path}",
        last_modified: now,
        page_count: 1
      })

    {book, bf}
  end
end
