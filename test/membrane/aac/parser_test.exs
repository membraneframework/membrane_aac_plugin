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
             sample_rate: 44_100,
             samples_per_frame: 1024
           }

    output =
      1..432
      |> Enum.map_join(fn _i ->
        assert_sink_buffer(pipeline, :sink, buffer)
        buffer.payload
      end)

    assert output == File.read!("test/fixtures/sample.aac")
    assert_end_of_stream(pipeline, :sink)
    refute_sink_caps(pipeline, :sink, _, 0)
    refute_sink_buffer(pipeline, :sink, _, 0)

    Testing.Pipeline.stop_and_terminate(pipeline, blocking?: true)
  end

  test "correct aac caps are generated in response to Membrane.AAC.RemoteStream caps" do
    {:ok, state} =
      Parser.handle_init(%Parser{
        out_encapsulation: :none,
        in_encapsulation: :none
      })

    input_caps = %Membrane.AAC.RemoteStream{
      audio_specific_config: <<
        ## AAC Low Complexity
        2::5,
        ## Sampling frequency index - 44 100 Hz
        4::4,
        # Channel configuration - stereo
        2::4,
        # frame length - 960 samples
        0b100
      >>
    }

    assert {{:ok, caps: {:output, caps}}, _state} =
             Parser.handle_caps(:input, input_caps, nil, state)

    assert %Membrane.AAC{profile: :LC, sample_rate: 44_100, channels: 2, samples_per_frame: 960} =
             caps
  end
end
