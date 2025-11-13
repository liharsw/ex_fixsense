defmodule ExFixsense.Protocol.DateUtil do
  @moduledoc """
  FIX protocol date/time utilities.

  Provides serialization and parsing for FIX standard timestamp formats.

  ## FIX Timestamp Formats

  FIX 4.4 uses two main timestamp formats:

  - **UTCTimestamp** (without milliseconds): `YYYYMMDD-HH:MM:SS`
    - Used for: SendingTime (52), TransactTime (60)
    - Example: `20250104-14:30:45`

  - **UTCTimestamp with milliseconds**: `YYYYMMDD-HH:MM:SS.mmm`
    - Used for: Some advanced fields
    - Example: `20250104-14:30:45.123`

  ## Examples

      iex> DateUtil.serialize(~U[2025-01-04 14:30:45Z])
      "20250104-14:30:45"

      iex> DateUtil.serialize(~U[2025-01-04 14:30:45.123Z], include_millis: true)
      "20250104-14:30:45.123"

      iex> DateUtil.parse("20250104-14:30:45")
      {:ok, ~U[2025-01-04 14:30:45Z]}
  """

  @doc """
  Serialize DateTime to FIX format.

  ## Parameters

  - `dt` - DateTime struct (must be UTC)
  - `opts` - Options:
    - `:include_millis` - Include milliseconds (default: false)

  ## Returns

  String in FIX timestamp format

  ## Examples

      iex> DateUtil.serialize(~U[2025-01-04 14:30:45Z])
      "20250104-14:30:45"

      iex> DateUtil.serialize(~U[2025-01-04 14:30:45.123Z], include_millis: true)
      "20250104-14:30:45.123"
  """
  def serialize(%DateTime{} = dt, opts \\ []) do
    # Ensure UTC timezone
    dt = DateTime.shift_zone!(dt, "Etc/UTC")

    include_millis = Keyword.get(opts, :include_millis, false)

    base =
      "#{pad4(dt.year)}#{pad2(dt.month)}#{pad2(dt.day)}-" <>
        "#{pad2(dt.hour)}:#{pad2(dt.minute)}:#{pad2(dt.second)}"

    if include_millis do
      millis = div(elem(dt.microsecond, 0), 1000)
      "#{base}.#{pad3(millis)}"
    else
      base
    end
  end

  @doc """
  Generate current UTC timestamp in FIX format.

  This is a convenience function for the most common use case.

  ## Parameters

  - `opts` - Options (same as serialize/2)

  ## Returns

  String in FIX timestamp format

  ## Examples

      iex> DateUtil.now()
      "20250104-14:30:45"

      iex> DateUtil.now(include_millis: true)
      "20250104-14:30:45.123"
  """
  def now(opts \\ []) do
    DateTime.utc_now() |> serialize(opts)
  end

  @doc """
  Parse FIX timestamp format to DateTime.

  Supports both formats:
  - `YYYYMMDD-HH:MM:SS`
  - `YYYYMMDD-HH:MM:SS.mmm`

  ## Parameters

  - `fix_str` - FIX timestamp string

  ## Returns

  - `{:ok, datetime}` - Successfully parsed
  - `{:error, reason}` - Parse failed

  ## Examples

      iex> DateUtil.parse("20250104-14:30:45")
      {:ok, ~U[2025-01-04 14:30:45Z]}

      iex> DateUtil.parse("20250104-14:30:45.123")
      {:ok, ~U[2025-01-04 14:30:45.123Z]}

      iex> DateUtil.parse("invalid")
      {:error, :invalid_format}
  """
  def parse(fix_str) when is_binary(fix_str) do
    case String.split(fix_str, ".") do
      [base_time] ->
        # Format: YYYYMMDD-HH:MM:SS
        parse_base(base_time, 0)

      [base_time, millis_str] ->
        # Format: YYYYMMDD-HH:MM:SS.mmm
        case Integer.parse(millis_str) do
          {millis, ""} -> parse_base(base_time, millis * 1000)
          _ -> {:error, :invalid_milliseconds}
        end

      _ ->
        {:error, :invalid_format}
    end
  rescue
    _ -> {:error, :invalid_format}
  end

  # Parse base timestamp without milliseconds
  defp parse_base(base_time, microsecond) do
    with {:ok, year, month, day, time_part} <- parse_date_part(base_time),
         {:ok, hour, minute, second} <- parse_time_part(time_part),
         {:ok, date} <- Date.new(year, month, day),
         {:ok, time} <- Time.new(hour, minute, second, {microsecond, 3}),
         {:ok, naive_dt} <- NaiveDateTime.new(date, time),
         {:ok, dt} <- DateTime.from_naive(naive_dt, "Etc/UTC") do
      {:ok, dt}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_format}
    end
  rescue
    _ -> {:error, :invalid_format}
  end

  # Parse date portion: YYYYMMDD-
  defp parse_date_part(str) do
    case String.split(str, "-", parts: 2) do
      [date_part, time_part] when byte_size(date_part) == 8 ->
        <<year::binary-size(4), month::binary-size(2), day::binary-size(2)>> = date_part

        {:ok, String.to_integer(year), String.to_integer(month), String.to_integer(day),
         time_part}

      _ ->
        {:error, :invalid_date_format}
    end
  end

  # Parse time portion: HH:MM:SS
  defp parse_time_part(str) do
    case String.split(str, ":") do
      [hour, minute, second] ->
        {:ok, String.to_integer(hour), String.to_integer(minute), String.to_integer(second)}

      _ ->
        {:error, :invalid_time_format}
    end
  end

  # Padding helpers
  defp pad2(num), do: String.pad_leading(Integer.to_string(num), 2, "0")
  defp pad3(num), do: String.pad_leading(Integer.to_string(num), 3, "0")
  defp pad4(num), do: String.pad_leading(Integer.to_string(num), 4, "0")
end
