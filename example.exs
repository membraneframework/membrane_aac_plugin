Mix.install([
  :membrane_core,
  :membrane_hackney_plugin,
  :membrane_mp4_plugin,
  :membrane_file_plugin,
  {:membrane_aac_plugin, path: Path.expand("./"), override: true}
])

defmodule Example do
  use Membrane.Pipeline

  alias Membrane.{AAC, File, Hackney, MP4}

  @impl true
  def handle_init(_) do
    children = [
      source: %Hackney.Source{
        location:
          "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/test-audio.aac",
        hackney_opts: [follow_redirect: true]
      },
      # filler is optional, included only for demonstration purposes
      parser: %AAC.Parser{out_encapsulation: :none},
      filler: AAC.Filler,
      payloader: MP4.Payloader.AAC,
      muxer: MP4.Muxer.ISOM,
      sink: %File.Sink{location: "out.mp4"}
    ]

    links = [
      link(:source)
      |> to(:parser)
      |> to(:filler)
      |> to(:payloader)
      |> to(:muxer)
      |> to(:sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}, playback: :play}, %{}}
  end

  # When end of stream arrives, kill the pipeline
  @impl
  def handle_element_end_of_stream({:sink, _pad}, _ctx, state) do
    __MODULE__.terminate(self())
    {:ok, state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _ctx, state) do
    {:ok, state}
  end
end

{:ok, pid} = Example.start_link()
monitor_ref = Process.monitor(pid)

receive do
  {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
    :ok
end
