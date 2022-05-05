defmodule Membrane.AAC.ParserTest do
  use ExUnit.Case
  import Membrane.Testing.Assertions
  alias Membrane.AAC.Parser
  alias Membrane.Testing

  @expected_timestamps [
    0,
    Ratio.new(10_240_000_000, 441),
    Ratio.new(20_480_000_000, 441),
    Ratio.new(10_240_000_000, 147),
    Ratio.new(40_960_000_000, 441),
    Ratio.new(51_200_000_000, 441)
  ]

  test "integration" do
    children = [
      file: %Membrane.File.Source{location: "test/fixtures/sample.aac"},
      parser: Parser,
      sink: Testing.Sink
    ]

    options = [links: Membrane.ParentSpec.link_linear(children)]
    assert {:ok, pipeline} = Testing.Pipeline.start_link(options)

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

    output_buffers =
      1..432
      |> Enum.map(fn _i ->
        assert_sink_buffer(pipeline, :sink, %Membrane.Buffer{pts: pts, dts: nil} = buffer)
        refute is_nil(pts)
        buffer
      end)

    output = Enum.map_join(output_buffers, & &1.payload)

    assert @expected_timestamps ==
             Enum.map(output_buffers, & &1.pts) |> Enum.take(length(@expected_timestamps))

    assert output == File.read!("test/fixtures/sample.aac")
    assert_end_of_stream(pipeline, :sink)
    refute_sink_caps(pipeline, :sink, _, 0)
    refute_sink_buffer(pipeline, :sink, _, 0)

    Testing.Pipeline.terminate(pipeline, blocking?: true)
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
        # GASpecificConfig
        # frame length - 960 samples
        1::1,
        # dependsOnCoreCoder
        0::1,
        # extensionFlag
        0::1
      >>
    }

    assert {{:ok, caps: {:output, caps}}, _state} =
             Parser.handle_caps(:input, input_caps, nil, state)

    assert %Membrane.AAC{profile: :LC, sample_rate: 44_100, channels: 2, samples_per_frame: 960} =
             caps
  end
end
