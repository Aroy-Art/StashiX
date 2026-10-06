defmodule StashixWeb.AdminLive.Users do
  @moduledoc """
  Users tab: accounts, roles and per-library permissions.

  Markup only: `StashixWeb.AdminLive` owns the state and handles every event.
  """
  use StashixWeb, :html

  alias Stashix.Formatters

  attr :current_user, :any, required: true
  attr :libraries, :any, required: true
  attr :saved_permissions, :any, required: true
  attr :selected_perm_user_id, :any, required: true
  attr :show_user_form, :any, required: true
  attr :user_permissions, :any, required: true
  attr :users, :any, required: true

  def tab(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="flex items-center justify-between">
        <.display_heading level={1} class="text-4xl!">Users</.display_heading>
        <.ink_button
          size="md"
          phx-click="toggle_user_form"
        >
          Add User
        </.ink_button>
      </div>

      <%= if @show_user_form do %>
        <div class="bg-gray-900 border border-white/15 rounded-lg p-6">
          <h3 class="font-display font-black uppercase text-2xl leading-none text-white mb-4">Create User</h3>
          <form phx-submit="create_user" class="grid grid-cols-2 gap-4">
            <.field label="Email">
              <.text_input type="email" name="email" required />
            </.field>
            <.field label="Username">
              <.text_input name="username" required />
            </.field>
            <.field label="Password">
              <.text_input type="password" name="password" required minlength="8" />
            </.field>
            <.field label="Role">
              <.ink_select
                id="new-user-role"
                name="role"
                label="Role"
                variant="field"
                value="user"
                options={[{"User", "user"}, {"Admin", "admin"}]}
              />
            </.field>
            <div class="col-span-2 flex gap-2 justify-end">
              <.ink_button variant="ghost" size="md" type="button" phx-click="toggle_user_form">Cancel</.ink_button>
              <.ink_button
                size="md"
                type="submit"
              >Create</.ink_button>
            </div>
          </form>
        </div>
      <% end %>

      <div class="bg-gray-900 rounded-lg ring-1 ring-white/10 overflow-hidden">
        <table class="w-full text-sm">
          <thead>
            <tr class="border-b border-white/10">
              <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">
                Username
              </th>
              <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Email</th>
              <th class="px-4 py-3 text-left text-[10px] font-bold tracking-[0.18em] uppercase text-gray-400">Role</th>
              <th class="px-4 py-3"></th>
            </tr>
          </thead>
          <tbody>
            <%= for user <- @users do %>
              <% perm_open = @selected_perm_user_id == user.id
              age_ratings = [:unknown, :everyone, :teen, :teen_plus, :mature, :adult, :explicit] %>
              <tr class="border-b border-white/10">
                <td class="px-4 py-3 text-white">{user.username}</td>
                <td class="px-4 py-3 text-gray-400">{user.email}</td>
                <td class="px-4 py-3">
                  <span class={[
                    "px-2 py-0.5 rounded text-xs font-medium",
                    if(user.role == :admin,
                      do: "bg-violet-900 text-violet-300",
                      else: "bg-gray-800 text-gray-400"
                    )
                  ]}>
                    {user.role}
                  </span>
                </td>
                <td class="px-4 py-3 text-right">
                  <div class="flex items-center gap-3 justify-end">
                    <%= if user.role != :admin do %>
                      <button
                        phx-click="show_user_permissions"
                        phx-value-id={user.id}
                        class={[
                          "text-xs transition-colors",
                          if(perm_open,
                            do: "text-violet-400 hover:text-violet-300",
                            else: "text-gray-400 hover:text-white"
                          )
                        ]}
                      >
                        Permissions
                      </button>
                    <% end %>
                    <%= if user.id != @current_user.id do %>
                      <.ink_button
                        variant="danger"
                        size="md"
                        phx-click="show_confirm"
                        phx-value-event="delete_user"
                        phx-value-id={user.id}
                        phx-value-title="Delete User"
                        phx-value-message={"Delete user \"#{user.username}\"? This cannot be undone."}
                        phx-value-label="Delete"
                      >
                        Delete
                      </.ink_button>
                    <% end %>
                  </div>
                </td>
              </tr>
              <%= if perm_open do %>
                <tr class="border-b border-white/10 bg-gray-950">
                  <td colspan="4" class="px-4 py-4">
                    <div class="space-y-2">
                      <p class="text-xs font-medium text-gray-400 uppercase tracking-wide mb-3">
                        Library Access for {user.username}
                      </p>
                      <%= if @libraries == [] do %>
                        <p class="text-sm text-gray-400">No libraries configured.</p>
                      <% else %>
                        <%= for lib <- @libraries do %>
                          <% perm = Map.get(@user_permissions, lib.id)
                          saved = MapSet.member?(@saved_permissions, "#{user.id}-#{lib.id}")
                          current_rating = if perm, do: perm.max_age_rating, else: :unknown

                          rating_opts =
                            Enum.map(age_ratings, &{Formatters.format_age_rating(&1), &1}) %>
                          <form
                            id={"permission-form-#{user.id}-#{lib.id}"}
                            phx-change="set_permission"
                            class="flex items-center justify-between py-2 px-3 rounded-lg bg-gray-900 border border-white/10"
                          >
                            <input type="hidden" name="user_id" value={user.id} />
                            <input type="hidden" name="library_id" value={lib.id} />
                            <div>
                              <p class="text-sm text-white">{lib.name}</p>
                              <p class="text-xs text-gray-400">{lib.root_path}</p>
                            </div>
                            <div class="flex items-center gap-4">
                              <%= if saved do %>
                                <span class="text-xs text-emerald-400 font-medium">✓ Saved</span>
                              <% end %>
                              <label class="flex items-center gap-2 cursor-pointer text-xs text-gray-400">
                                <input
                                  type="checkbox"
                                  name="can_read"
                                  value="true"
                                  checked={perm != nil && perm.can_read}
                                  class="ink-check"
                                /> Can read
                              </label>
                              <div class="w-40">
                                <.ink_select
                                  id={"rating-#{user.id}-#{lib.id}"}
                                  name="max_age_rating"
                                  label="Maximum age rating"
                                  variant="field"
                                  size="sm"
                                  value={current_rating}
                                  options={rating_opts}
                                />
                              </div>
                              <label
                                class={[
                                  "flex items-center gap-2 text-xs",
                                  if(current_rating == :unknown,
                                    do: "text-gray-400 cursor-not-allowed",
                                    else: "text-gray-400 cursor-pointer"
                                  )
                                ]}
                                title="Unrated books are shown under an age limit unless this is checked"
                              >
                                <input
                                  type="checkbox"
                                  name="hide_unrated"
                                  value="true"
                                  checked={perm != nil && perm.hide_unrated}
                                  disabled={current_rating == :unknown}
                                  class="ink-check"
                                /> Hide unrated
                              </label>
                            </div>
                          </form>
                        <% end %>
                      <% end %>
                    </div>
                  </td>
                </tr>
              <% end %>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
    """
  end
end
