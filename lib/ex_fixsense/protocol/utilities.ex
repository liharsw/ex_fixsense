defmodule ExFixsense.Protocol.Utilities do
  @moduledoc """
  Common utilities for FIX protocol operations.

  Provides UTC timestamp formatting in FIX standard format.
  """

  alias ExFixsense.Protocol.DateUtil

  @doc """
  Generate FIX standard UTC timestamp with millisecond precision.

  Format: YYYYMMDD-HH:MM:SS.mmm

  This is the format required by FIX 4.4 for SendingTime (tag 52),
  TransactTime (tag 60), and other timestamp fields.

  Delegates to `ExFixsense.Protocol.DateUtil.now/1` with millisecond precision.

  ## Returns
  String in format "20250103-14:30:45.123"

  ## Example
      iex> utc_timestamp()
      "20250103-14:30:45.123"
  """
  def utc_timestamp do
    DateUtil.now(include_millis: true)
  end
end
