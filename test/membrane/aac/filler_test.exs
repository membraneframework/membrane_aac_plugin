defmodule Membrane.AAC.FillerTest do
  use ExUnit.Case
  alias Membrane.AAC.Filler
  alias Membrane.Buffer
  alias Membrane.Testing.{Pipeline, Source, Sink}

  @single_channel 1

  describe "Filler element" do
    setup _ do
      current_timestamp = 2
      state = %Filler.State{frame_duration: 1, expected_timestamp: current_timestamp}
      [state: state, current_timestamp: current_timestamp]
    end

    test "does not fill when it is not needed", %{
      state: state,
      current_timestamp: current_timestamp
    } do
      current_buffer = %Buffer{metadata: %{timestamp: current_timestamp}, payload: ""}

      assert {{:ok, actions}, new_state} =
               Filler.handle_process(:input, current_buffer, nil, state)

      assert actions == [buffer: {:output, [current_buffer]}]
      # No silent frames increment by 1
      assert new_state.expected_timestamp == current_timestamp + state.frame_duration
    end

    test "fills the gap if there is one", %{
      state: state,
      current_timestamp: current_timestamp
    } do
      skipped_frames = 10

      current_buffer = %Buffer{
        metadata: %{timestamp: current_timestamp + skipped_frames},
        payload: ""
      }

      assert {{:ok, buffer: {:output, buffers}}, new_state} =
               Filler.handle_process(:input, current_buffer, nil, state)

      assert new_state.expected_timestamp ==
               current_timestamp + skipped_frames + state.frame_duration

      {silent_frames, [original_buffer]} = Enum.split(buffers, skipped_frames)
      assert original_buffer == current_buffer
      assert Enum.count(silent_frames) == skipped_frames

      assert Enum.all?(silent_frames, fn buffer ->
               assert buffer.payload == Filler.silent_frame(@single_channel)
             end)
    end

    test "works in a pipeline" do
      import Membrane.Testing.Assertions

      non_empty_timestamps = [0, 1, 3, 4, 7, 10, 15]

      buffers =
        non_empty_timestamps
        |> Enum.map(
          &%Membrane.Buffer{
            payload: &1,
            metadata: %{timestamp: &1}
          }
        )

      caps = %Membrane.AAC{
        profile: :LC,
        # Values samples_per_frame and sample_rate are set to constants
        # that will result in Filler element state frame_duration field equal 1
        samples_per_frame: 1,
        sample_rate: Membrane.Time.second(),
        channels: 1
      }

      children = [
        source: %Source{output: Source.output_from_buffers(buffers), caps: caps},
        tested_element: Filler,
        sink: %Sink{}
      ]

      options = [links: Membrane.ParentSpec.link_linear(children)]

      {:ok, pipeline} = Pipeline.start_link(options)

      for number <- List.first(non_empty_timestamps)..List.last(non_empty_timestamps) do
        expected_payload =
          if number in non_empty_timestamps do
            number
          else
            Filler.silent_frame(@single_channel)
          end

        assert_sink_buffer(pipeline, :sink, %Buffer{payload: received_payload})
        assert expected_payload == received_payload
      end

      assert_end_of_stream(pipeline, :sink)
      refute_sink_buffer(pipeline, :sink, _, 0)

      Pipeline.terminate(pipeline, blocking?: true)
    end

    test "selects proper silent frame", %{
      state: state,
      current_timestamp: current_timestamp
    } do
      skipped_frames = 1

      generate_first_silent_frame = fn channels ->
        state = %{state | channels: channels}

        buffer = %Buffer{
          metadata: %{timestamp: current_timestamp + skipped_frames},
          payload: ""
        }

        {{:ok, buffer: {:output, buffers}}, _state} =
          Filler.handle_process(:input, buffer, nil, state)

        List.first(buffers) |> Map.fetch!(:payload)
      end

      channels_cfgs = [1, 2]

      Enum.each(channels_cfgs, fn channels ->
        assert Filler.silent_frame(channels) == generate_first_silent_frame.(channels)
      end)
    end
  end
end
