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
      muxer: MP4.Muxer,
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

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end
end

ref =
  Example.start_link()
  |> elem(1)
  |> tap(&Membrane.Pipeline.play/1)
  |> then(&Process.monitor/1)

receive do
  {:DOWN, ^ref, :process, _pid, _reason} ->
    :ok
end
