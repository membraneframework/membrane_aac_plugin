defmodule Membrane.AAC.ParserTest do
  @moduledoc false
  
  use ExUnit.Case
  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions
  alias Membrane.AAC.Parser
  alias Membrane.{AAC, Testing}
  alias Membrane.Testing.Pipeline

  @expected_timestamps [
    0,
    Ratio.new(10_240_000_000, 441),
    Ratio.new(20_480_000_000, 441),
    Ratio.new(10_240_000_000, 147),
    Ratio.new(40_960_000_000, 441),
    Ratio.new(51_200_000_000, 441)
  ]

  defp perform_conversion_test(comparison_config, transition_config) do
    fixture_pipeline_structure =
      child(:file, %Membrane.File.Source{location: "test/fixtures/sample.aac"})
      |> child(:parser, %Parser{output_config: comparison_config})
      |> child(:sink, Testing.Sink)

    conversion_pipeline_structure =
      child(:file, %Membrane.File.Source{location: "test/fixtures/sample.aac"})
      |> child(:parser1, %Parser{output_config: transition_config})
      |> child(:parser2, %Parser{output_config: comparison_config})
      |> child(:sink, Testing.Sink)

    fixture_pipeline_pid = Pipeline.start_link_supervised!(structure: fixture_pipeline_structure)

    conversion_pipeline_pid =
      Pipeline.start_link_supervised!(structure: conversion_pipeline_structure)

    assert_pipeline_play(fixture_pipeline_pid)

    assert_sink_stream_format(fixture_pipeline_pid, :sink, %AAC{
      config: {^comparison_config, fixture_config}
    })

    assert_end_of_stream(fixture_pipeline_pid, :sink)

    assert_pipeline_play(conversion_pipeline_pid)

    assert_sink_stream_format(conversion_pipeline_pid, :sink, %AAC{
      config: {^comparison_config, ^fixture_config}
    })

    assert_end_of_stream(conversion_pipeline_pid, :sink)

    Pipeline.terminate(fixture_pipeline_pid)
    Pipeline.terminate(conversion_pipeline_pid)
  end

  test "integration" do
    pipeline =
      Testing.Pipeline.start_link_supervised!(
        structure:
          child(:file, %Membrane.File.Source{location: "test/fixtures/sample.aac"})
          |> child(:parser, Parser)
          |> child(:sink, Testing.Sink)
      )

    assert_pipeline_play(pipeline)
    assert_sink_stream_format(pipeline, :sink, stream_format)

    assert stream_format == %Membrane.AAC{
             channels: 1,
             encapsulation: :ADTS,
             frames_per_buffer: 1,
             mpeg_version: 4,
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
    refute_sink_stream_format(pipeline, :sink, _, 0)
    refute_sink_buffer(pipeline, :sink, _, 0)

    Testing.Pipeline.terminate(pipeline, blocking?: true)
  end

  test "correct AAC stream format is generated in response to provided audio specific config" do
    {_actions, state} =
      Parser.handle_init(nil, %Parser{
        out_encapsulation: :none,
        in_encapsulation: :none
      })

    input_stream_format = %AAC{
      config:
        {:audio_specific_config,
         <<
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
         >>}
    }

    assert {[stream_format: {:output, output_stream_format}], _state} =
             Parser.handle_stream_format(:input, input_stream_format, nil, state)

    assert %AAC{profile: :LC, sample_rate: 44_100, channels: 2, samples_per_frame: 960} =
             output_stream_format
  end

  test "the output stream format is the same as input when converting between configs" do
    perform_conversion_test(:esds, :audio_specific_config)
    perform_conversion_test(:audio_specific_config, :esds)
  end
end
