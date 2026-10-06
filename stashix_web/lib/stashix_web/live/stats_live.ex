defmodule StashixWeb.StatsLive do
  use StashixWeb, :live_view

  alias Stashix.Library

  on_mount {StashixWeb.Live.Hooks, :require_auth}

  @impl true
  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_user.id
    access = socket.assigns.access

    by_year = Library.stats_books_by_year(access)
    by_type = Library.stats_books_by_type(access)
    by_month = Library.stats_added_by_month(access)
    reading = Library.stats_reading_progress(access, user_id)
    top_series = Library.stats_top_series(access, 15)
    by_file_format = Library.stats_books_by_file_format(access)
    size_by_publisher = Library.stats_file_size_by_publisher(access)
    by_language = Library.stats_books_by_language(access)
    by_age_rating = Library.stats_books_by_age_rating(access)
    top_genres = Library.stats_top_genres(access, 20)
    top_creators = Library.stats_top_creators(access, 20)
    credits_by_role = Library.stats_credits_by_role(access)
    top_characters = Library.stats_top_characters(access, 20)
    top_publishers = Library.stats_top_publishers_by_count(access, 20)
    total_pages = Library.stats_total_pages(access)
    total_file_size = Library.stats_total_file_size(access)
    metadata = Library.stats_metadata_coverage(access)

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
    do: ["#7c3aed", "#4fe8eb", "#c4b5fd", "#f59e0b", "#f43f5e", "#34d399", "#60a5fa", "#94a3b8"]

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
        "splitLine" => %{"lineStyle" => %{"color" => "rgba(255,255,255,0.08)"}}
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
        "splitLine" => %{"lineStyle" => %{"color" => "rgba(255,255,255,0.08)"}}
      },
      "series" => [
        %{
          "type" => "bar",
          "data" => counts,
          "itemStyle" => %{"color" => "#4fe8eb", "borderRadius" => [3, 3, 0, 0]}
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
      "series" => [pie_series(data, ["#4b5563", "#7c3aed", "#22c55e"])]
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
        "splitLine" => %{"lineStyle" => %{"color" => "rgba(255,255,255,0.08)"}}
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
        "splitLine" => %{"lineStyle" => %{"color" => "rgba(255,255,255,0.08)"}}
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
          "itemStyle" => %{"color" => "#4fe8eb", "borderRadius" => [0, 3, 3, 0]}
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
        "splitLine" => %{"lineStyle" => %{"color" => "rgba(255,255,255,0.08)"}}
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
        "splitLine" => %{"lineStyle" => %{"color" => "rgba(255,255,255,0.08)"}}
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
          "itemStyle" => %{"color" => "#4fe8eb", "borderRadius" => [0, 3, 3, 0]}
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
        "splitLine" => %{"lineStyle" => %{"color" => "rgba(255,255,255,0.08)"}}
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

  defp shorten(str, max) when byte_size(str) > max, do: String.slice(str, 0, max - 1) <> "…"
  defp shorten(str, _), do: str

  defp title_case(str) do
    str
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :option, :map, required: true
  attr :height, :string, default: "h-56"
  attr :class, :any, default: nil

  # A chart in a plain panel. The Chart hook owns the element once mounted.
  defp chart_card(assigns) do
    ~H"""
    <.panel class={["p-4 sm:p-5", @class]}>
      <.eyebrow tag="h2" tone="light" class="mb-3">{@title}</.eyebrow>
      <div id={@id} phx-hook="Chart" phx-update="ignore" class={["w-full", @height]} data-option={Jason.encode!(@option)}>
      </div>
    </.panel>
    """
  end

  attr :label, :string, required: true
  attr :note, :string, default: nil
  attr :tone, :string, default: "text-white"
  slot :inner_block, required: true

  defp figure(assigns) do
    ~H"""
    <div class="min-w-0">
      <.eyebrow tag="dt" size="sm" tone="ink" class="mb-1">{@label}</.eyebrow>
      <dd class={["font-display font-black text-4xl leading-none tabular-nums", @tone]}>{render_slot(@inner_block)}</dd>
      <p :if={@note} class="mt-1 text-xs text-gray-400 tabular-nums">{@note}</p>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page wide>
      <.page_hero title="Stats" eyebrow="Your stash in numbers" count={@stats.total_books > 0 && @stats.total_books} />

      <.panel variant="indicia">
        <dl class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-x-8 gap-y-6 px-6 py-6">
          <.figure label="Total" note="books & issues">{format_number(@stats.total_books)}</.figure>
          <.figure label="Unread" note={pct(@stats.unread, @stats.total_books)} tone="text-gray-300">
            {format_number(@stats.unread)}
          </.figure>
          <.figure label="In progress" note={pct(@stats.in_progress, @stats.total_books)} tone="text-violet-300">
            {format_number(@stats.in_progress)}
          </.figure>
          <.figure label="Completed" note={pct(@stats.completed, @stats.total_books)} tone="text-green-400">
            {format_number(@stats.completed)}
          </.figure>
          <.figure label="Pages" note="across all files">{format_number(@stats.total_pages)}</.figure>
          <.figure label="Size" note="total storage">
            {Stashix.Formatters.format_bytes(Decimal.to_integer(@stats.total_file_size))}
          </.figure>
        </dl>
      </.panel>

      <%!-- Fun fact, lettered like a narrator's caption --%>
      <div>
        <p class="reader-end-caption inline-block max-w-2xl px-4 py-2.5 bg-ink text-zinc-950 text-sm sm:text-base font-semibold leading-snug">
          Meanwhile, at the printer: your whole library on A4 would take
          <span class="font-display font-black text-xl tabular-nums">{format_number(@stats.paper_sheets)}</span>
          sheets weighing <span class="font-display font-black text-xl">{@stats.paper_weight}</span>.
        </p>
        <p class="mt-3 text-xs text-gray-400 tabular-nums">
          {format_number(@stats.total_pages)} pages ÷ 2 sides × 5 g a sheet (A4, 80 gsm)
        </p>
      </div>

      <.section title="Metadata coverage">
        <.panel class="p-5">
          <dl class="grid grid-cols-2 lg:grid-cols-4 gap-x-8 gap-y-6">
            <div
              :for={
                {label, count} <- [
                  {"With summary", @stats.metadata.with_summary},
                  {"With genres", @stats.metadata.with_genres},
                  {"With credits", @stats.metadata.with_credits},
                  {"With external ids", @stats.metadata.with_external_ids}
                ]
              }
              class="min-w-0"
            >
              <.eyebrow tag="dt" size="sm" tone="muted" class="mb-1">{label}</.eyebrow>
              <dd class="font-display font-black text-3xl leading-none text-white tabular-nums">
                {pct(count, @stats.metadata.total)}
              </dd>
              <.progress_bar
                value={if @stats.metadata.total > 0, do: count / @stats.metadata.total, else: 0.0}
                class="h-1 mt-2"
              />
              <p class="mt-1.5 text-xs text-gray-400 tabular-nums">{count} of {@stats.metadata.total}</p>
            </div>
          </dl>
        </.panel>
      </.section>

      <.section title="Over time">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <.chart_card id="chart_by_month" title="Added by month" option={@chart_by_month} />
          <.chart_card id="chart_by_year" title="Publication year" option={@chart_by_year} />
        </div>
      </.section>

      <.section title="Breakdown">
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          <.chart_card id="chart_by_type" title="Type" option={@chart_by_type} />
          <.chart_card id="chart_reading" title="Reading progress" option={@chart_reading} />
          <.chart_card id="chart_by_format" title="File formats" option={@chart_by_format} />
          <.chart_card id="chart_by_language" title="Language" option={@chart_by_language} />
          <.chart_card id="chart_by_age_rating" title="Age rating" option={@chart_by_age_rating} />
          <.chart_card id="chart_credits_by_role" title="Credits by role" option={@chart_credits_by_role} />
        </div>
      </.section>

      <.section title="Top of the stash">
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <.chart_card
            id="chart_top_series"
            title="Series by issue count"
            option={@chart_top_series}
            height="h-96"
            class="lg:col-span-2"
          />
          <.chart_card id="chart_top_creators" title="Creators by credits" option={@chart_top_creators} height="h-96" />
          <.chart_card id="chart_top_genres" title="Genres" option={@chart_top_genres} height="h-96" />
          <.chart_card id="chart_top_characters" title="Characters" option={@chart_top_characters} height="h-96" />
          <.chart_card
            id="chart_top_publishers"
            title="Publishers by book count"
            option={@chart_top_publishers}
            height="h-96"
          />
          <.chart_card
            id="chart_size_by_publisher"
            title="File size by publisher"
            option={@chart_size_by_publisher}
            height="h-[50rem] lg:h-[28rem]"
            class="lg:col-span-2"
          />
        </div>
      </.section>
    </.page>
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
