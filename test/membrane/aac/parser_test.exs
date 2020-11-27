defmodule Membrane.AAC.ParserTest do
  use ExUnit.Case
  import Membrane.Testing.Assertions
  alias Membrane.AAC.Parser
  alias Membrane.Testing

  test "integration" do
    children = [
      file: %Membrane.File.Source{location: "test/fixtures/sample.aac"},
      parser: Parser,
      sink: Testing.Sink
    ]

    assert {:ok, pipeline} =
             Testing.Pipeline.start_link(%Testing.Pipeline.Options{
               elements: children
             })

    :ok = Testing.Pipeline.play(pipeline)
    assert_pipeline_playback_changed(pipeline, _, :playing)
    assert_sink_caps(pipeline, :sink, caps)

    assert caps == %Membrane.AAC{
             channels: 1,
             encapsulation: :ADTS,
             frames_per_buffer: 1,
             mpeg_version: 2,
             profile: :LC,
             sample_rate: 44100,
             samples_per_frame: 1024
           }

    output =
      1..432
      |> Enum.map(fn _ ->
        assert_sink_buffer(pipeline, :sink, buffer)
        buffer.payload
      end)
      |> Enum.join()

    assert output == File.read!("test/fixtures/sample.aac")
    assert_end_of_stream(pipeline, :sink)
    refute_sink_caps(pipeline, :sink, _, 0)
    refute_sink_buffer(pipeline, :sink, _, 0)
  end
end
