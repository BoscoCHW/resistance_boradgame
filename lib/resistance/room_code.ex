defmodule Resistance.RoomCode do
  @moduledoc """
  Handles generation and validation of 6-character room codes.
  Room codes use alphanumeric characters (excluding ambiguous ones: 0, O, I, l).
  """

  # Characters to use: A-Z and 2-9 (excluding 0, O, I, 1 to avoid confusion)
  @charset "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
           |> String.graphemes()

  @doc """
  Generates a new random 6-character room code.
  Uses uppercase letters and numbers, excluding confusing characters.

  ## Examples
      iex> code = Resistance.RoomCode.generate()
      iex> String.length(code)
      6
  """
  def generate do
    1..6
    |> Enum.map(fn _ -> Enum.random(@charset) end)
    |> Enum.join()
  end

  @doc """
  Validates a room code format.
  Returns {:ok, normalized_code} or {:error, message}.

  ## Examples
      iex> Resistance.RoomCode.validate("ABC123")
      {:ok, "ABC123"}

      iex> Resistance.RoomCode.validate("abc")
      {:error, "Room code must be exactly 6 characters"}

      iex> Resistance.RoomCode.validate("ABC!@#")
      {:error, "Room code can only contain letters and numbers"}
  """
  def validate(code) when is_binary(code) do
    normalized = String.upcase(String.trim(code))

    cond do
      String.length(normalized) != 6 ->
        {:error, "Room code must be exactly 6 characters"}

      !Regex.match?(~r/^[A-Z0-9]+$/, normalized) ->
        {:error, "Room code can only contain letters and numbers"}

      true ->
        {:ok, normalized}
    end
  end

  def validate(_), do: {:error, "Invalid room code format"}

  @doc """
  Returns the PubSub topic name for a given room code.
  """
  def pubsub_topic(room_code), do: "room:#{room_code}"

  @doc """
  Returns the Registry key for a pregame server.
  """
  def pregame_key(room_code), do: {:pregame, room_code}

  @doc """
  Returns the Registry key for a game server.
  """
  def game_key(room_code), do: {:game, room_code}
end
