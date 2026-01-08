defmodule ResistanceWeb.HomeLive do
  use ResistanceWeb, :live_view
  require Logger

  @impl true
  def mount(_params, session, socket) do
    init_state =
      socket
      |> assign(:self, session["_csrf_token"])
      |> assign(:form, to_form(%{"name" => "", "room_code" => ""}))
      |> assign(:is_creating, false)
      |> assign(:is_full, false)
      |> assign(:muted, false)
      |> assign(:music_file, "home-music.mp3")

    {:ok, init_state}
  end

  @impl true
  def handle_event("validate", params, socket) do
    name = Map.get(params, "name", "")
    room_code = Map.get(params, "room_code", "")

    # Validate name if not empty
    name_errors = if name != "" do
      validate_name_format(name)
    else
      []
    end

    # Validate room code if joining (not creating) and code is not empty
    room_code_errors = if !socket.assigns.is_creating && room_code != "" do
      case Resistance.RoomCode.validate(room_code) do
        {:error, msg} -> [room_code: {msg, []}]
        _ -> []
      end
    else
      []
    end

    all_errors = name_errors ++ room_code_errors

    {:noreply, assign(socket, :form, to_form(params, errors: all_errors))}
  end

  @impl true
  def handle_event("create_mode", _params, socket) do
    {:noreply, assign(socket, :is_creating, true)}
  end

  @impl true
  def handle_event("join_mode", _params, socket) do
    {:noreply, assign(socket, :is_creating, false)}
  end

  @impl true
  def handle_event("join", %{"name" => name} = param, socket) do
    # Get the room code - either from creating (socket.assigns) or from form input
    final_room_code = if socket.assigns.is_creating do
      Resistance.RoomCode.generate()
    else
      Map.get(param, "room_code", "")
    end

    case Resistance.RoomCode.validate(final_room_code) do
      {:ok, normalized_code} ->
        case Pregame.Server.add_player(normalized_code, socket.assigns.self, String.trim(name)) do
          :lobby_full ->
            {:noreply, socket |> assign(:is_full, true)}

          :game_in_progress ->
            # TODO: Show Game in Progress Modal
            {:noreply, socket}

          {:error, msg} ->
            {:noreply, assign(socket, :form, to_form(param, errors: [name: {msg, []}]))}

          _ ->
            {:noreply, push_navigate(socket, to: "/lobby/#{normalized_code}")}
        end

      {:error, msg} ->
        {:noreply, assign(socket, :form, to_form(param, errors: [room_code: {msg, []}]))}
    end
  end

  # Local name format validation (without checking if taken)
  defp validate_name_format(name) do
    cond do
      !Regex.match?(~r/^[a-zA-Z0-9_ ]+$/, name) ->
        [name: {"Name can only contain letters, numbers, spaces, and underscores.", []}]

      !Regex.match?(~r/^.{4,12}$/, name) ->
        [name: {"Name must be between 4-12 characters long.", []}]

      true ->
        []
    end
  end
end
