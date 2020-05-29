defmodule Membrane.AAC.Parser do
  @moduledoc """
  Parser for Advanced Audio Codec. Currently works only for ADTS-encapsulated AAC.
  """
  use Membrane.Filter
  alias __MODULE__.Helper
  alias Membrane.AAC

  def_input_pad :input, demand_unit: :bytes, caps: :any
  def_output_pad :output, caps: {AAC, samples_per_frame: 1024}

  def_options samples_per_frame: [
                spec: 1024 | 960,
                default: 1024,
                description: "Count of audio samples in each AAC frame"
              ],
              out_encapsulation: [
                spec: AAC.encapsulation_t(),
                default: :ADTS,
                description: """
                Determines whether output AAC frames should be prepended with ADTS headers
                """
              ]

  @impl true
  def handle_init(options) do
    state = options |> Map.from_struct() |> Map.merge(%{leftover: <<>>, timestamp: 0})
    {:ok, state}
  end

  @impl true
  def handle_caps(:input, _caps, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_process(:input, buffer, ctx, state) do
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

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size * 2048}}, state}
  end
end
