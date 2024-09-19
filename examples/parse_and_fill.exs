Mix.install([
  :membrane_hackney_plugin,
  :membrane_mp4_plugin,
  :membrane_file_plugin,
  {:membrane_aac_plugin, path: Path.expand("./"), override: true}
])

defmodule FillingWithSilencePipeline do
  use Membrane.Pipeline

  alias Membrane.{AAC, File, Hackney}

  @impl true
  def handle_init(_ctx, _opts) do
    spec =
      child(:source, %Hackney.Source{
        location:
          "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/test-audio.aac",
        hackney_opts: [follow_redirect: true]
      })
      |> child(:parser, %AAC.Parser{out_encapsulation: :ADTS})
      |> child(:filler, AAC.Filler)
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
