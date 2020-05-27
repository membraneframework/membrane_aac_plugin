defmodule Membrane.AAC.Parser do
  @moduledoc """
  Parser for Advanced Audio Codec. Currently works only for ADTS-encapsulated AAC.
  """
  use Membrane.Filter
  alias __MODULE__.Helper
  alias Membrane.Buffer

  def_input_pad :input, demand_unit: :bytes, caps: :any
  def_output_pad :output, caps: {Membrane.AAC, samples_per_frame: 1024}

  def_options samples_per_frame: [
                spec: 1024 | 960,
                default: 1024,
                description: "Count of audio samples in each AAC frame"
              ]

  @impl true
  def handle_init(options) do
    {:ok, options |> Map.from_struct() |> Map.merge(%{leftover: <<>>})}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, ctx, state) do
    %{caps: caps} = ctx.pads.output
    parse_opts = Map.take(state, [:samples_per_frame])

    with {:ok, {output, leftover}} <-
           Helper.parse_adts(state.leftover <> payload, caps, parse_opts) do
      actions = Enum.map(output, fn {action, value} -> {action, {:output, value}} end)
      {{:ok, actions ++ [redemand: :output]}, %{state | leftover: leftover}}
    else
      {:error, reason} -> {{:error, reason}, state}
    end
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size * 2048}}, state}
  end
end
