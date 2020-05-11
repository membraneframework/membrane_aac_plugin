defmodule Membrane.AAC.Filler do
  use Membrane.Filter
  alias Membrane.{Buffer, Time}

  @silent_frame <<222, 2, 0, 76, 97, 118, 99, 53, 56, 46, 53, 52, 46, 49, 48, 48, 0, 2, 48, 64,
                  14>>

  @caps {Membrane.Caps.Audio.AAC,
         profile: :LC, samples_per_frame: 1024, sample_rate: 44100, channels: 1}

  def_input_pad :input, demand_unit: :buffers, caps: @caps
  def_output_pad :output, caps: @caps

  def_options init_timestamp: [default: nil]

  @impl true
  def handle_init(opts) do
    {:ok, %{expected_timestamp: opts.init_timestamp, frame_duration: nil}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_caps(:input, caps, _ctx, state) do
    state = %{state | frame_duration: caps.samples_per_frame / caps.sample_rate * Time.second()}
    {{:ok, forward: caps}, state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) do
    use Ratio, comparison: true

    %{timestamp: current_timestamp} = buffer.metadata
    %{expected_timestamp: expected_timestamp, frame_duration: frame_duration} = state
    expected_timestamp = expected_timestamp || current_timestamp

    silent_frames_timestamps =
      Stream.iterate(expected_timestamp, &(&1 + frame_duration))
      |> Enum.take_while(&silent_frame_needed?(&1, current_timestamp, frame_duration))

    buffers =
      Enum.map(silent_frames_timestamps, fn timestamp ->
        %Buffer{buffer | payload: @silent_frame}
        |> Bunch.Struct.put_in([:metadata, :timestamp], timestamp)
      end) ++ [buffer]

    expected_timestamp = expected_timestamp + length(buffers) * frame_duration

    {{:ok, buffer: {:output, buffers}}, %{state | expected_timestamp: expected_timestamp}}
  end

  defp silent_frame_needed?(expected_timestamp, current_timestamp, frame_duration) do
    use Ratio, comparison: true
    current_timestamp - expected_timestamp > frame_duration / 2
  end
end
