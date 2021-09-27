defmodule Membrane.AAC.Parser do
  @moduledoc """
  Parser for Advanced Audio Codec.

  Supports both plain and ADTS-encapsulated output (configured by `out_encapsulation`),
  but currently accepts only ADTS AAC input.
  Input with encapsulation :none is supported, but correct AAC caps need to be supplied with the stream.

  Adds sample rate based timestamp to metadata if absent.
  """
  use Membrane.Filter
  alias __MODULE__.Helper
  alias Membrane.AAC

  def_input_pad :input, demand_unit: :bytes, caps: :any
  def_output_pad :output, caps: AAC

  def_options samples_per_frame: [
                spec: AAC.samples_per_frame_t(),
                default: 1024,
                description: "Count of audio samples in each AAC frame"
              ],
              out_encapsulation: [
                spec: AAC.encapsulation_t(),
                default: :ADTS,
                description: """
                Determines whether output AAC frames should be prefixed with ADTS headers
                """
              ],
              in_encapsulation: [
                spec: AAC.encapsulation_t(),
                default: :ADTS
              ]

  @type timestamp_t :: Ratio.t() | Membrane.Time.t()

  @impl true
  def handle_init(options) do
    state = options |> Map.from_struct() |> Map.merge(%{leftover: <<>>, timestamp: 0})
    {:ok, state}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, state) when state.in_encapsulation == :none do
    case caps do
      %AAC{encapsulation: :none} ->
        {{:ok, caps: {:output, %{caps | encapsulation: state.out_encapsulation}}}, state}

      _other ->
        raise(
          "%AAC{encapsulation: :none} caps are required when declaring in_encapsulation as :none"
        )
    end
  end

  def handle_caps(:input, _caps, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(:input, buffer, ctx, state) when state.in_encapsulation == :ADTS do
    %{caps: caps} = ctx.pads.output
    timestamp = Map.get(buffer.metadata, :timestamp, state.timestamp)
    parse_opts = Map.take(state, [:samples_per_frame, :out_encapsulation])

    with {:ok, {output, leftover, timestamp}} <-
           Helper.parse_adts(state.leftover <> buffer.payload, caps, timestamp, parse_opts) do
      actions = Enum.map(output, fn {action, value} -> {action, {:output, value}} end)
      {{:ok, actions ++ [redemand: :output]}, %{state | leftover: leftover, timestamp: timestamp}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  def handle_process(:input, buffer, ctx, state) when state.in_encapsulation == :none do
    # Since there is no ADTS header, there is nothing to parse on the input
    # Therefore, we only really add the timestamp
    timestamp = Helper.next_timestamp(state.timestamp, ctx.pads.input.caps)
    metadata = Map.put(buffer.metadata, :timestamp, timestamp)
    buffer = %{buffer | metadata: metadata}
    {{:ok, buffer: {:output, buffer}}, %{state | timestamp: timestamp}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size * 2048}}, state}
  end
end
