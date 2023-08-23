defmodule Membrane.AAC.Parser do
  @moduledoc """
  Parser for Advanced Audio Codec.

  Supports both plain and ADTS-encapsulated output (configured by `out_encapsulation`).
  Input with encapsulation `:none` is supported, but correct AAC stream format needs to be supplied with the stream.

  If PTS is absent, it calculates and puts one based on the sample rate.
  """
  use Membrane.Filter
  alias __MODULE__.{ADTS, Config}
  alias Membrane.{AAC, Buffer}

  def_input_pad :input,
    demand_unit: :buffers,
    accepted_format: any_of(AAC, Membrane.RemoteStream)


  def_output_pad :output, accepted_format: AAC

  def_options samples_per_frame: [
                spec: AAC.samples_per_frame(),
                default: 1024,
                description: "Count of audio samples in each AAC frame"
              ],
              out_encapsulation: [
                spec: AAC.encapsulation(),
                default: :ADTS,
                description: """
                Determines whether output AAC frames should be prefixed with ADTS headers
                """
              ],
              in_encapsulation: [
                spec: AAC.encapsulation(),
                default: :ADTS
              ],
              avg_bit_rate: [
                spec: non_neg_integer(),
                default: 0,
                description: "Average stream bitrate. Should be set to 0 if unknown."
              ],
              max_bit_rate: [
                spec: non_neg_integer(),
                default: 0,
                description: "Maximum stream bitrate. Should be set to 0 if unknown."
              ],
              output_config: [
                spec: :esds | :audio_specific_config | nil,
                default: nil,
                description: """
                  Determines which config structure will be generated and included in
                  output stream format as `config`.
                """
              ]

  @type timestamp :: Ratio.t() | Membrane.Time.t()

  @impl true
  def handle_init(_ctx, options) do
    state = options |> Map.from_struct() |> Map.merge(%{leftover: <<>>, timestamp: 0})
    {[], state}
  end

  @impl true
  def handle_stream_format(:input, %AAC{} = stream_format, _ctx, state) do
    if stream_format.encapsulation != state.in_encapsulation do
      raise("""
      %AAC{encapsulation: #{inspect(state.in_encapsulation)}} stream format is required when declaring in_encapsulation
      as #{inspect(state.in_encapsulation)}. Got %AAC{encapsulation: #{inspect(stream_format.encapsulation)}}).
      """)
    end

    stream_format = Config.parse_config(stream_format)

    config = Config.generate_config(stream_format, state)

    {[
       stream_format:
         {:output, %{stream_format | encapsulation: state.out_encapsulation, config: config}}
     ], state}
  end

  @impl true
  def handle_stream_format(:input, %Membrane.RemoteStream{} = stream_format, _ctx, state) do
    if state.in_encapsulation == :none and state.out_encapsulation == :ADTS do
      raise """
        Not supported parser configuration
        for the stream format: #{inspect(stream_format)}:
        `in_encapsulation: :none`, `out_encapsulation: :ADTS`

        There is no way to fetch metadata required by ADTS encapsulation,
        such as number of channels or the sampling frequency, directly
        from the stream with `in_encapsulation: :none`, neither has the metadata
        been provided in the stream format.
      """
    end

    {[], state}
  end

  @impl true
  def handle_process(:input, buffer, ctx, %{in_encapsulation: :ADTS} = state) do
    %{stream_format: stream_format} = ctx.pads.output
    timestamp = buffer.pts || state.timestamp

    case ADTS.parse_adts(state.leftover <> buffer.payload, stream_format, timestamp, state) do
      {:ok, {output, leftover, timestamp}} ->
        actions = Enum.map(output, fn {action, value} -> {action, {:output, value}} end)

        {actions ++ [redemand: :output], %{state | leftover: leftover, timestamp: timestamp}}

      {:error, reason} ->
        raise "Could not parse incoming buffer due to #{inspect(reason)}"
    end
  end

  @impl true
  def handle_process(:input, buffer, ctx, %{in_encapsulation: :none} = state) do
    timestamp = buffer.pts || ADTS.next_timestamp(state.timestamp, ctx.pads.output.stream_format)

    buffer = %{buffer | pts: timestamp}

    buffer =
      case state.out_encapsulation do
        :ADTS ->
          %Buffer{
            buffer
            | payload: ADTS.payload_to_adts(buffer.payload, ctx.pads.output.stream_format)
          }

        _other ->
          buffer
      end

    {[buffer: {:output, buffer}], %{state | timestamp: timestamp}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {[demand: {:input, size}], state}
  end
end
