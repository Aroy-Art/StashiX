defmodule StashixWeb.StatsLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id

    by_year = Library.stats_books_by_year()
    by_type = Library.stats_books_by_type()
    by_month = Library.stats_added_by_month()
    reading = Library.stats_reading_progress(user_id)
    top_series = Library.stats_top_series(15)
    by_format = Library.stats_series_by_format()

    {:ok,
     assign(socket,
       page_title: "Stats",
       chart_by_year: build_by_year(by_year),
       chart_by_type: build_by_type(by_type),
       chart_by_month: build_by_month(by_month),
       chart_reading: build_reading(reading),
       chart_top_series: build_top_series(top_series),
       chart_by_format: build_by_format(by_format),
       stats: %{
         total_books: reading.total,
         unread: reading.unread,
         in_progress: reading.in_progress,
         completed: reading.completed
       }
     )}
  end

  # ECharts option builders

  defp grid_opts do
    %{"left" => "4%", "right" => "4%", "bottom" => "12%", "top" => "8%", "containLabel" => true}
  end

  defp build_by_year([]) do
    %{"series" => [], "xAxis" => %{"data" => []}, "yAxis" => %{}}
  end

  defp build_by_year(rows) do
    years = Enum.map(rows, fn {y, _} -> to_string(y) end)
    counts = Enum.map(rows, fn {_, c} -> c end)

    %{
      "grid" => grid_opts(),
      "tooltip" => %{"trigger" => "axis"},
      "xAxis" => %{
        "type" => "category",
        "data" => years,
        "axisLabel" => %{"color" => "#6b7280", "rotate" => 45}
      },
      "yAxis" => %{
        "type" => "value",
        "splitLine" => %{"lineStyle" => %{"color" => "#1f2937"}}
      },
      "series" => [
        %{
          "type" => "bar",
          "data" => counts,
          "itemStyle" => %{"color" => "#7c3aed", "borderRadius" => [3, 3, 0, 0]}
        }
      ]
    }
  end

  defp build_by_type([]) do
    %{"series" => [%{"data" => []}]}
  end

  defp build_by_type(rows) do
    data =
      Enum.map(rows, fn {type, count} ->
        label =
          case type do
            "issue" -> "Issues"
            "standalone" -> "Books"
            other -> String.capitalize(other)
          end

        %{"name" => label, "value" => count}
      end)

    %{
      "tooltip" => %{"trigger" => "item"},
      "legend" => %{
        "orient" => "horizontal",
        "bottom" => 0,
        "textStyle" => %{"color" => "#9ca3af"}
      },
      "series" => [
        %{
          "type" => "pie",
          "radius" => ["40%", "70%"],
          "center" => ["50%", "45%"],
          "data" => data,
          "itemStyle" => %{
            "borderRadius" => 4,
            "borderColor" => "#030712",
            "borderWidth" => 2
          },
          "label" => %{"color" => "#9ca3af"},
          "color" => ["#7c3aed", "#06b6d4", "#10b981", "#f59e0b", "#ef4444"]
        }
      ]
    }
  end

  defp build_by_month([]) do
    %{"series" => [], "xAxis" => %{"data" => []}, "yAxis" => %{}}
  end

  defp build_by_month(rows) do
    months = Enum.map(rows, fn {m, _} -> m end)
    counts = Enum.map(rows, fn {_, c} -> c end)

    %{
      "grid" => grid_opts(),
      "tooltip" => %{"trigger" => "axis"},
      "xAxis" => %{
        "type" => "category",
        "data" => months,
        "axisLabel" => %{"color" => "#6b7280", "rotate" => 45}
      },
      "yAxis" => %{
        "type" => "value",
        "splitLine" => %{"lineStyle" => %{"color" => "#1f2937"}}
      },
      "series" => [
        %{
          "type" => "bar",
          "data" => counts,
          "itemStyle" => %{"color" => "#2563eb", "borderRadius" => [3, 3, 0, 0]}
        }
      ]
    }
  end

  defp build_reading(%{total: 0}) do
    %{"series" => [%{"data" => []}]}
  end

  defp build_reading(%{unread: unread, in_progress: in_progress, completed: completed}) do
    %{
      "tooltip" => %{"trigger" => "item"},
      "legend" => %{
        "orient" => "horizontal",
        "bottom" => 0,
        "textStyle" => %{"color" => "#9ca3af"}
      },
      "series" => [
        %{
          "type" => "pie",
          "radius" => ["40%", "70%"],
          "center" => ["50%", "45%"],
          "data" => [
            %{"name" => "Unread", "value" => unread},
            %{"name" => "In Progress", "value" => in_progress},
            %{"name" => "Completed", "value" => completed}
          ],
          "itemStyle" => %{
            "borderRadius" => 4,
            "borderColor" => "#030712",
            "borderWidth" => 2
          },
          "label" => %{"color" => "#9ca3af"},
          "color" => ["#4b5563", "#7c3aed", "#10b981"]
        }
      ]
    }
  end

  defp build_top_series([]) do
    %{"series" => [], "yAxis" => %{"data" => []}, "xAxis" => %{}}
  end

  defp build_top_series(rows) do
    names = rows |> Enum.map(fn {name, _} -> shorten(name, 30) end) |> Enum.reverse()
    counts = rows |> Enum.map(fn {_, c} -> c end) |> Enum.reverse()

    %{
      "grid" => %{
        "left" => "2%",
        "right" => "4%",
        "bottom" => "4%",
        "top" => "4%",
        "containLabel" => true
      },
      "tooltip" => %{"trigger" => "axis", "axisPointer" => %{"type" => "shadow"}},
      "xAxis" => %{
        "type" => "value",
        "splitLine" => %{"lineStyle" => %{"color" => "#1f2937"}}
      },
      "yAxis" => %{
        "type" => "category",
        "data" => names,
        "axisLabel" => %{"color" => "#9ca3af", "fontSize" => 11}
      },
      "series" => [
        %{
          "type" => "bar",
          "data" => counts,
          "itemStyle" => %{"color" => "#7c3aed", "borderRadius" => [0, 3, 3, 0]}
        }
      ]
    }
  end

  defp build_by_format([]) do
    %{"series" => [%{"data" => []}]}
  end

  defp build_by_format(rows) do
    data =
      Enum.map(rows, fn {fmt, count} ->
        %{"name" => fmt_label(fmt), "value" => count}
      end)

    %{
      "tooltip" => %{"trigger" => "item"},
      "legend" => %{
        "orient" => "horizontal",
        "bottom" => 0,
        "textStyle" => %{"color" => "#9ca3af"}
      },
      "series" => [
        %{
          "type" => "pie",
          "radius" => ["35%", "65%"],
          "center" => ["50%", "45%"],
          "data" => data,
          "itemStyle" => %{
            "borderRadius" => 4,
            "borderColor" => "#030712",
            "borderWidth" => 2
          },
          "label" => %{"color" => "#9ca3af"},
          "color" => ["#7c3aed", "#06b6d4", "#10b981", "#f59e0b", "#ef4444", "#8b5cf6", "#3b82f6"]
        }
      ]
    }
  end

  defp shorten(str, max) when byte_size(str) > max, do: String.slice(str, 0, max - 1) <> "…"
  defp shorten(str, _), do: str

  defp fmt_label(fmt) when is_atom(fmt), do: fmt |> Atom.to_string() |> fmt_label()
  defp fmt_label("comic_series"), do: "Comic Series"
  defp fmt_label("graphic_novel"), do: "Graphic Novel"
  defp fmt_label("trade_paperback"), do: "Trade Paperback"
  defp fmt_label("manga"), do: "Manga"
  defp fmt_label("mini_series"), do: "Mini-Series"
  defp fmt_label(other), do: other |> String.replace("_", " ") |> String.capitalize()

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6 pb-8">
      <%!-- Header --%>
      <div>
        <h1 class="text-2xl md:text-3xl font-bold text-white flex items-center gap-3">
          <.icon name="lucide-chart-bar" class="w-7 h-7 text-violet-400" /> Stats
        </h1>
      </div>

      <%!-- Summary tiles --%>
      <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider mb-1">Total</p>
          <p class="text-2xl font-bold text-white">{@stats.total_books}</p>
          <p class="text-xs text-gray-600 mt-0.5">books & issues</p>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider mb-1">Unread</p>
          <p class="text-2xl font-bold text-gray-400">{@stats.unread}</p>
          <p class="text-xs text-gray-600 mt-0.5">
            {pct(@stats.unread, @stats.total_books)}
          </p>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider mb-1">In Progress</p>
          <p class="text-2xl font-bold text-violet-400">{@stats.in_progress}</p>
          <p class="text-xs text-gray-600 mt-0.5">
            {pct(@stats.in_progress, @stats.total_books)}
          </p>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider mb-1">Completed</p>
          <p class="text-2xl font-bold text-green-400">{@stats.completed}</p>
          <p class="text-xs text-gray-600 mt-0.5">
            {pct(@stats.completed, @stats.total_books)}
          </p>
        </div>
      </div>

      <%!-- Charts row 1 --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Added by Month</h2>
          <div
            id="chart_by_month"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-56"
            data-option={Jason.encode!(@chart_by_month)}
          >
          </div>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Publication Year</h2>
          <div
            id="chart_by_year"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-56"
            data-option={Jason.encode!(@chart_by_year)}
          >
          </div>
        </div>
      </div>

      <%!-- Charts row 2 --%>
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-4">
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Type Breakdown</h2>
          <div
            id="chart_by_type"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-56"
            data-option={Jason.encode!(@chart_by_type)}
          >
          </div>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Reading Progress</h2>
          <div
            id="chart_reading"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-56"
            data-option={Jason.encode!(@chart_reading)}
          >
          </div>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Series by Format</h2>
          <div
            id="chart_by_format"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-56"
            data-option={Jason.encode!(@chart_by_format)}
          >
          </div>
        </div>
      </div>

      <%!-- Top series --%>
      <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
        <h2 class="text-sm font-semibold text-gray-400 mb-3">Top Series by Issue Count</h2>
        <div
          id="chart_top_series"
          phx-hook="Chart"
          phx-update="ignore"
          class="w-full h-96"
          data-option={Jason.encode!(@chart_top_series)}
        >
        </div>
      </div>
    </div>
    """
  end

  defp pct(_, 0), do: "—"
  defp pct(n, total), do: "#{round(n / total * 100)}%"
end
