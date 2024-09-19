defmodule Membrane.AAC.Filler do
  @moduledoc """
  ** Warning: This element is deprecated. **

  ** Please use `Membrane.AudioFiller` from the `:membrane_audio_filler_plugin` to fill gaps in raw audio stream with silence. **

  Element that fills gaps in AAC stream with silent frames.
  """
  use Membrane.Filter
  alias Membrane.{Buffer, Time}
  require Membrane.Logger

  # Silence frame per channel configuration
  @silent_frames %{
    1 => <<222, 2, 0, 76, 97, 118, 99, 54, 48, 46, 51, 49, 46, 49, 48, 50, 0, 2, 48, 64, 14>>,
    2 =>
      <<255, 241, 80, 128, 3, 223, 252, 222, 2, 0, 76, 97, 118, 99, 53, 56, 46, 57, 49, 46, 49,
        48, 48, 0, 66, 32, 8, 193, 24, 56>>
  }

  @accepted_format quote(
                     do: %Membrane.AAC{profile: :LC, channels: channels} when channels in [1, 2]
                   )

  def_input_pad :input,
    flow_control: :manual,
    demand_unit: :buffers,
    accepted_format: unquote(@accepted_format)

  def_output_pad :output, flow_control: :manual, accepted_format: unquote(@accepted_format)

  defmodule State do
    @moduledoc false

    # Membrane normalizes timestamps and stream always starts with timestamp 0.
    @initial_timestamp 0
    @default_channels 1

    @type t :: %__MODULE__{
            frame_duration: Membrane.Time.t(),
            channels: non_neg_integer(),
            expected_timestamp: non_neg_integer()
          }

    @enforce_keys [:frame_duration]
    defstruct [expected_timestamp: @initial_timestamp, channels: @default_channels] ++
                @enforce_keys
  end

  @doc """
  Returns a silent AAC frame that this element uses to fill gaps in the stream.
  """
  @spec silent_frame(integer()) :: binary()
  @deprecated "This function is no longer supported"
  def silent_frame(channels), do: Map.fetch!(@silent_frames, channels)

  @impl true
  def handle_init(_ctx, _opts) do
    Membrane.Logger.warning("""
    `#{__MODULE__}` element is deprecated now.
    Please use `Membrane.AudioFiller` from the `:membrane_audio_filler_plugin` to fill gaps in raw audio stream with silence.
    """)

    {[], %State{frame_duration: nil}}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    {[demand: {:input, size}], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    new_duration =
      stream_format.samples_per_frame / stream_format.sample_rate * Time.second()

    state = %State{state | frame_duration: new_duration, channels: stream_format.channels}

    {[forward: stream_format], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    use Numbers, overload_operators: true, comparison: true

    current_timestamp = buffer.pts || buffer.dts
    %{expected_timestamp: expected_timestamp, frame_duration: frame_duration} = state
    expected_timestamp = expected_timestamp || current_timestamp

    silent_frames_timestamps =
      Stream.iterate(expected_timestamp, &(&1 + frame_duration))
      |> Enum.take_while(&silent_frame_needed?(&1, current_timestamp, frame_duration))

    silent_frame_payload = silent_frame(state.channels)

    buffers =
      Enum.map(silent_frames_timestamps, fn timestamp ->
        %Buffer{
          buffer
          | payload: silent_frame_payload,
            pts: round(timestamp),
            dts: round(timestamp)
        }
      end) ++ [buffer]

    expected_timestamp = expected_timestamp + length(buffers) * frame_duration

    {[buffer: {:output, buffers}], %{state | expected_timestamp: expected_timestamp}}
  end

  defp silent_frame_needed?(expected_timestamp, current_timestamp, frame_duration) do
    use Numbers, overload_operators: true, comparison: true
    current_timestamp - expected_timestamp > frame_duration / 2
  end
end
