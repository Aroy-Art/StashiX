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
    by_file_format = Library.stats_books_by_file_format()
    size_by_publisher = Library.stats_file_size_by_publisher()
    by_language = Library.stats_books_by_language()
    by_age_rating = Library.stats_books_by_age_rating()
    top_genres = Library.stats_top_genres(20)
    top_creators = Library.stats_top_creators(20)
    credits_by_role = Library.stats_credits_by_role()
    top_characters = Library.stats_top_characters(20)
    top_publishers = Library.stats_top_publishers_by_count(20)
    total_pages = Library.stats_total_pages()
    total_file_size = Library.stats_total_file_size()
    metadata = Library.stats_metadata_coverage()

    {:ok,
     assign(socket,
       page_title: "Stats",
       chart_by_year: build_by_year(by_year),
       chart_by_type: build_by_type(by_type),
       chart_by_month: build_by_month(by_month),
       chart_reading: build_reading(reading),
       chart_top_series: build_top_series(top_series),
       chart_by_format: build_by_file_format(by_file_format),
       chart_size_by_publisher: build_size_by_publisher(size_by_publisher),
       chart_by_language: build_by_language(by_language),
       chart_by_age_rating: build_by_age_rating(by_age_rating),
       chart_top_genres: build_top_genres(top_genres),
       chart_top_creators: build_top_creators(top_creators),
       chart_credits_by_role: build_credits_by_role(credits_by_role),
       chart_top_characters: build_top_characters(top_characters),
       chart_top_publishers: build_top_publishers(top_publishers),
       stats: %{
         total_books: reading.total,
         unread: reading.unread,
         in_progress: reading.in_progress,
         completed: reading.completed,
         total_pages: total_pages || 0,
         total_file_size: total_file_size || Decimal.new(0),
         metadata: metadata,
         paper_weight: Stashix.Formatters.format_paper_weight(total_pages || 0),
         paper_sheets: Stashix.Formatters.paper_sheets(total_pages || 0)
       }
     )}
  end

  # ECharts option builders

  defp grid_opts do
    %{"left" => "4%", "right" => "4%", "bottom" => "12%", "top" => "8%", "containLabel" => true}
  end

  defp grid_opts_horizontal do
    %{"left" => "2%", "right" => "4%", "bottom" => "4%", "top" => "4%", "containLabel" => true}
  end

  defp pie_series(data, colors) do
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
      "color" => colors
    }
  end

  defp default_colors,
    do: ["#7c3aed", "#06b6d4", "#10b981", "#f59e0b", "#ef4444", "#4f46e5", "#0e7490", "#047857"]

  defp legend_opts do
    %{"orient" => "horizontal", "bottom" => 0, "textStyle" => %{"color" => "#9ca3af"}}
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
      "legend" => legend_opts(),
      "series" => [pie_series(data, default_colors())]
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
    data = [
      %{"name" => "Unread", "value" => unread},
      %{"name" => "In Progress", "value" => in_progress},
      %{"name" => "Completed", "value" => completed}
    ]

    %{
      "tooltip" => %{"trigger" => "item"},
      "legend" => legend_opts(),
      "series" => [pie_series(data, ["#4b5563", "#7c3aed", "#10b981"])]
    }
  end

  defp build_top_series([]) do
    %{"series" => [], "yAxis" => %{"data" => []}, "xAxis" => %{}}
  end

  defp build_top_series(rows) do
    names = rows |> Enum.map(fn {name, _} -> shorten(name, 30) end) |> Enum.reverse()
    counts = rows |> Enum.map(fn {_, c} -> c end) |> Enum.reverse()

    %{
      "grid" => grid_opts_horizontal(),
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

  defp build_by_file_format([]) do
    %{"series" => [%{"data" => []}]}
  end

  defp build_by_file_format(rows) do
    data =
      Enum.map(rows, fn {fmt, count} ->
        %{"name" => fmt |> Atom.to_string() |> String.upcase(), "value" => count}
      end)

    %{
      "tooltip" => %{"trigger" => "item"},
      "legend" => legend_opts(),
      "series" => [
        %{pie_series(data, default_colors()) | "radius" => ["35%", "65%"]}
      ]
    }
  end

  defp build_size_by_publisher([]) do
    %{"series" => [%{"type" => "treemap", "data" => []}]}
  end

  defp build_size_by_publisher(rows) do
    data =
      rows
      |> Enum.filter(fn {_, _, size} -> size && Decimal.compare(size, 0) == :gt end)
      |> Enum.map(fn {id, name, size} ->
        bytes = Decimal.to_integer(size)
        formatted = Stashix.Formatters.format_bytes(bytes)

        %{
          "name" => name,
          "value" => bytes,
          "link" => "/publisher/#{id}",
          "tooltip" => %{"formatter" => "#{name}: #{formatted}"}
        }
      end)

    %{
      "tooltip" => %{"trigger" => "item"},
      "series" => [
        %{
          "type" => "treemap",
          "data" => data,
          "roam" => false,
          "nodeClick" => false,
          "cursor" => "pointer",
          "left" => 0,
          "right" => 0,
          "top" => 0,
          "bottom" => 0,
          "width" => "100%",
          "height" => "100%",
          "breadcrumb" => %{"show" => false},
          "label" => %{
            "show" => true,
            "color" => "#e5e7eb",
            "fontSize" => 11,
            "overflow" => "truncate"
          },
          "upperLabel" => %{"show" => false},
          "itemStyle" => %{"borderColor" => "#030712", "borderWidth" => 2, "gapWidth" => 2},
          "colorMappingBy" => "index",
          "levels" => [
            %{
              "itemStyle" => %{
                "borderColor" => "#1f2937",
                "borderWidth" => 0,
                "gapWidth" => 3
              },
              "color" => [
                "#7c3aed",
                "#2563eb",
                "#0891b2",
                "#059669",
                "#d97706",
                "#dc2626",
                "#4f46e5",
                "#0e7490",
                "#047857",
                "#b45309"
              ]
            }
          ]
        }
      ]
    }
  end

  defp build_by_language([]) do
    %{"series" => [%{"data" => []}]}
  end

  defp build_by_language(rows) do
    data =
      Enum.map(rows, fn {lang, count} ->
        %{"name" => lang |> to_string() |> String.upcase(), "value" => count}
      end)

    %{
      "tooltip" => %{"trigger" => "item"},
      "legend" => legend_opts(),
      "series" => [pie_series(data, default_colors())]
    }
  end

  defp build_by_age_rating([]) do
    %{"series" => [%{"data" => []}]}
  end

  defp build_by_age_rating(rows) do
    rating_label = fn r ->
      case r do
        :unknown -> "Unknown"
        :everyone -> "Everyone"
        :teen -> "Teen"
        :teen_plus -> "Teen+"
        :mature -> "Mature"
        :adult -> "Adult"
        :explicit -> "Explicit"
        other -> other |> Atom.to_string() |> title_case()
      end
    end

    data = Enum.map(rows, fn {r, c} -> %{"name" => rating_label.(r), "value" => c} end)

    %{
      "tooltip" => %{"trigger" => "item"},
      "legend" => legend_opts(),
      "series" => [
        pie_series(data, ["#4b5563", "#10b981", "#2563eb", "#7c3aed", "#f59e0b", "#ef4444", "#dc2626"])
      ]
    }
  end

  defp build_top_genres([]) do
    %{"series" => [], "yAxis" => %{"data" => []}, "xAxis" => %{}}
  end

  defp build_top_genres(rows) do
    names = rows |> Enum.map(fn {n, _} -> shorten(n, 25) end) |> Enum.reverse()
    counts = rows |> Enum.map(fn {_, c} -> c end) |> Enum.reverse()

    %{
      "grid" => grid_opts_horizontal(),
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
          "itemStyle" => %{"color" => "#06b6d4", "borderRadius" => [0, 3, 3, 0]}
        }
      ]
    }
  end

  defp build_top_creators([]) do
    %{"series" => [], "yAxis" => %{"data" => []}, "xAxis" => %{}}
  end

  defp build_top_creators(rows) do
    names = rows |> Enum.map(fn {n, _} -> shorten(n, 25) end) |> Enum.reverse()
    counts = rows |> Enum.map(fn {_, c} -> c end) |> Enum.reverse()

    %{
      "grid" => grid_opts_horizontal(),
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
          "itemStyle" => %{"color" => "#10b981", "borderRadius" => [0, 3, 3, 0]}
        }
      ]
    }
  end

  @role_groups %{
    "Writing" => ~w[Writer Script Story Plot Interviewer]a,
    "Art" => ~w[Artist Penciller Breakdowns Illustrator Layouts]a,
    "Inking" => [:Inker, :Embellisher, :Finishes, :"Ink Assists"],
    "Colouring" => [
      :Colorist,
      :"Color Separations",
      :"Color Assists",
      :"Color Flats",
      :"Digital Art Technician",
      :"Gray Tone"
    ],
    "Lettering" => ~w[Letterer]a,
    "Covers" => [:"Cover Artist"],
    "Editing" => [
      :Editor,
      :"Consulting Editor",
      :"Assistant Editor",
      :"Associate Editor",
      :"Group Editor",
      :"Senior Editor",
      :"Managing Editor",
      :"Collection Editor",
      :"Supervising Editor",
      :"Executive Editor",
      :"Editor in Chief"
    ],
    "Production" => [
      :Production,
      :Designer,
      :"Logo Design",
      :Translator,
      :"Executive Producer",
      :"General Manager",
      :"Production Manager",
      :"Brand Manager",
      :"VP of Business Affairs",
      :"VP of Marketing",
      :"VP of Publicity",
      :"VP of Sales",
      :"Chief Creative Officer",
      :President,
      :Publisher,
      :Other
    ]
  }

  defp role_group(role) do
    Enum.find_value(@role_groups, "Other", fn {group, roles} ->
      if role in roles, do: group
    end)
  end

  defp build_credits_by_role([]) do
    %{"series" => [%{"data" => []}]}
  end

  defp build_credits_by_role(rows) do
    grouped =
      rows
      |> Enum.group_by(fn {role, _} -> role_group(role) end, fn {_, c} -> c end)
      |> Enum.map(fn {group, counts} -> {group, Enum.sum(counts)} end)
      |> Enum.sort_by(fn {_, c} -> c end, :desc)

    data = Enum.map(grouped, fn {group, count} -> %{"name" => group, "value" => count} end)

    %{
      "tooltip" => %{"trigger" => "item"},
      "series" => [
        pie_series(data, [
          "#7c3aed",
          "#2563eb",
          "#06b6d4",
          "#10b981",
          "#f59e0b",
          "#ef4444",
          "#8b5cf6",
          "#64748b"
        ])
      ]
    }
  end

  defp build_top_characters([]) do
    %{"series" => [], "yAxis" => %{"data" => []}, "xAxis" => %{}}
  end

  defp build_top_characters(rows) do
    names = rows |> Enum.map(fn {n, _} -> shorten(n, 25) end) |> Enum.reverse()
    counts = rows |> Enum.map(fn {_, c} -> c end) |> Enum.reverse()

    %{
      "grid" => grid_opts_horizontal(),
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
          "itemStyle" => %{"color" => "#f59e0b", "borderRadius" => [0, 3, 3, 0]}
        }
      ]
    }
  end

  defp build_top_publishers([]) do
    %{"series" => [], "yAxis" => %{"data" => []}, "xAxis" => %{}}
  end

  defp build_top_publishers(rows) do
    names = rows |> Enum.map(fn {_, n, _} -> shorten(n, 25) end) |> Enum.reverse()
    counts = rows |> Enum.map(fn {_, _, c} -> c end) |> Enum.reverse()

    %{
      "grid" => grid_opts_horizontal(),
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
          "itemStyle" => %{"color" => "#4f46e5", "borderRadius" => [0, 3, 3, 0]}
        }
      ]
    }
  end

  defp shorten(str, max) when byte_size(str) > max, do: String.slice(str, 0, max - 1) <> "…"
  defp shorten(str, _), do: str

  defp title_case(str) do
    str
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

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
      <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
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
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider mb-1">Total Pages</p>
          <p class="text-2xl font-bold text-cyan-400">{format_number(@stats.total_pages)}</p>
          <p class="text-xs text-gray-600 mt-0.5">across all files</p>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <p class="text-xs text-gray-500 uppercase tracking-wider mb-1">Library Size</p>
          <p class="text-2xl font-bold text-indigo-400">
            {Stashix.Formatters.format_bytes(Decimal.to_integer(@stats.total_file_size))}
          </p>
          <p class="text-xs text-gray-600 mt-0.5">total storage</p>
        </div>
      </div>

      <%!-- Fun fact: paper weight --%>
      <div class="bg-gray-900 border border-gray-800 rounded-xl p-4 flex flex-col sm:flex-row sm:items-center gap-3">
        <span class="text-2xl">📄</span>
        <div>
          <p class="text-xs text-gray-500 uppercase tracking-wider mb-0.5">Fun Fact · Paper Weight</p>
          <p class="text-white">
            If you printed your entire library on A4 paper you'd need
            <span class="font-bold text-violet-400">{format_number(@stats.paper_sheets)}</span>
            sheets weighing <span class="font-bold text-violet-400">{@stats.paper_weight}</span>.
          </p>
          <p class="text-xs text-gray-600 mt-0.5">
            {@stats.total_pages} pages ÷ 2 sides × 5 g/sheet (A4 80 gsm)
          </p>
        </div>
      </div>

      <%!-- Metadata coverage tiles --%>
      <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
        <h2 class="text-sm font-semibold text-gray-400 mb-3">Metadata Coverage</h2>
        <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div class="bg-gray-800 rounded-lg p-3">
            <p class="text-xs text-gray-500 mb-1">With Summary</p>
            <p class="text-xl font-bold text-white">
              {pct(@stats.metadata.with_summary, @stats.metadata.total)}
            </p>
            <p class="text-xs text-gray-600 mt-0.5">
              {@stats.metadata.with_summary} / {@stats.metadata.total}
            </p>
          </div>
          <div class="bg-gray-800 rounded-lg p-3">
            <p class="text-xs text-gray-500 mb-1">With Genres</p>
            <p class="text-xl font-bold text-white">
              {pct(@stats.metadata.with_genres, @stats.metadata.total)}
            </p>
            <p class="text-xs text-gray-600 mt-0.5">
              {@stats.metadata.with_genres} / {@stats.metadata.total}
            </p>
          </div>
          <div class="bg-gray-800 rounded-lg p-3">
            <p class="text-xs text-gray-500 mb-1">With Credits</p>
            <p class="text-xl font-bold text-white">
              {pct(@stats.metadata.with_credits, @stats.metadata.total)}
            </p>
            <p class="text-xs text-gray-600 mt-0.5">
              {@stats.metadata.with_credits} / {@stats.metadata.total}
            </p>
          </div>
          <div class="bg-gray-800 rounded-lg p-3">
            <p class="text-xs text-gray-500 mb-1">With External IDs</p>
            <p class="text-xl font-bold text-white">
              {pct(@stats.metadata.with_external_ids, @stats.metadata.total)}
            </p>
            <p class="text-xs text-gray-600 mt-0.5">
              {@stats.metadata.with_external_ids} / {@stats.metadata.total}
            </p>
          </div>
        </div>
      </div>

      <%!-- Charts row 1: timeline --%>
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

      <%!-- Pie charts: 2 rows × 3 cols --%>
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
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
          <h2 class="text-sm font-semibold text-gray-400 mb-3">File Formats</h2>
          <div
            id="chart_by_format"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-56"
            data-option={Jason.encode!(@chart_by_format)}
          >
          </div>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Language</h2>
          <div
            id="chart_by_language"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-56"
            data-option={Jason.encode!(@chart_by_language)}
          >
          </div>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Age Rating</h2>
          <div
            id="chart_by_age_rating"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-56"
            data-option={Jason.encode!(@chart_by_age_rating)}
          >
          </div>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Credits by Role</h2>
          <div
            id="chart_credits_by_role"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-56"
            data-option={Jason.encode!(@chart_credits_by_role)}
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

      <%!-- Top creators + top genres side by side --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Top Creators by Credits</h2>
          <div
            id="chart_top_creators"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-96"
            data-option={Jason.encode!(@chart_top_creators)}
          >
          </div>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Top Genres</h2>
          <div
            id="chart_top_genres"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-96"
            data-option={Jason.encode!(@chart_top_genres)}
          >
          </div>
        </div>
      </div>

      <%!-- Top characters + top publishers side by side --%>
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Top Characters</h2>
          <div
            id="chart_top_characters"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-96"
            data-option={Jason.encode!(@chart_top_characters)}
          >
          </div>
        </div>
        <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
          <h2 class="text-sm font-semibold text-gray-400 mb-3">Top Publishers by Book Count</h2>
          <div
            id="chart_top_publishers"
            phx-hook="Chart"
            phx-update="ignore"
            class="w-full h-96"
            data-option={Jason.encode!(@chart_top_publishers)}
          >
          </div>
        </div>
      </div>

      <%!-- File size treemap by publisher --%>
      <div class="bg-gray-900 border border-gray-800 rounded-xl p-4">
        <h2 class="text-sm font-semibold text-gray-400 mb-3">File Size by Publisher</h2>
        <div
          id="chart_size_by_publisher"
          phx-hook="Chart"
          phx-update="ignore"
          class="w-full h-[50rem] lg:h-[28rem]"
          data-option={Jason.encode!(@chart_size_by_publisher)}
        >
        </div>
      </div>
    </div>
    """
  end

  defp pct(_, 0), do: "—"
  defp pct(n, total), do: "#{round(n / total * 100)}%"

  defp format_number(n) when n >= 1_000_000,
    do: "#{:erlang.float_to_binary(n / 1_000_000, decimals: 1)}M"

  defp format_number(n) when n >= 1_000,
    do: "#{:erlang.float_to_binary(n / 1_000, decimals: 1)}K"

  defp format_number(n), do: to_string(n)
end
