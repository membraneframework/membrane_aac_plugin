defmodule Membrane.AAC.Parser.Utils do
  @moduledoc """
  __jm__ TODO
  """

  alias Membrane.{AAC, Buffer}

  @type timestamp :: Ratio.t() | Membrane.Time.t()

  @spec next_timestamp(any(), AAC.t()) :: timestamp()
  def next_timestamp(timestamp, stream_format) do
    use Numbers, overload_operators: true

    timestamp +
      Ratio.new(
        stream_format.samples_per_frame * stream_format.frames_per_buffer *
          Membrane.Time.second(),
        stream_format.sample_rate
      )
  end
end
