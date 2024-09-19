Mix.install([
  :membrane_hackney_plugin,
  :membrane_mp4_plugin,
  :membrane_file_plugin,
  {:membrane_aac_plugin, path: Path.expand("./"), override: true}
])

defmodule TimestampsGapGenerator do
  use Membrane.Filter

  def_input_pad :input, accepted_format: _any
  def_output_pad :output, accepted_format: _any

  def_options gap_duration: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.seconds(5),
                description: """
                Specifies the duration of the timestamps gap.
                """
              ],
              gap_start_time: [
                spec: Membrane.Time.t(),
                default: Membrane.Time.seconds(0),
                description: """
                Specifies when the timestamps gap should start.
                """
              ]

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    buffer =
      if buffer.pts > state.gap_start_time do
        %{buffer | pts: buffer.pts + state.gap_duration}
      else
        buffer
      end

    {[buffer: {:output, buffer}], state}
  end
end

defmodule FillingWithSilencePipeline do
  use Membrane.Pipeline

  alias Membrane.{AAC, File, Hackney}

  @impl true
  def handle_init(_ctx, _opts) do
    # child(%File.Source{location: "out.aac"})
    spec =
      child(:source, %Hackney.Source{
        location:
          "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/test-audio.aac",
        hackney_opts: [follow_redirect: true]
      })
      |> child(:parser, %AAC.Parser{out_encapsulation: :none})
      |> child(:timestamps_gap_generator, TimestampsGapGenerator)
      |> child(:filler, AAC.Filler)
      |> child(:parser2, %AAC.Parser{out_encapsulation: :ADTS})
      |> child(:sink, %File.Sink{location: "output.aac"})

    {[spec: spec], %{}}
  end

  # When end of stream arrives, terminate the pipeline
  @impl
  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(_child, _pad, _ctx, state) do
    {[], state}
  end
end

{:ok, _supervisor, pid} = Membrane.Pipeline.start_link(FillingWithSilencePipeline)
monitor_ref = Process.monitor(pid)

receive do
  {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
    :ok
end
