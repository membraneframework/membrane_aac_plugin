defmodule Membrane.AAC.FillerTest do
  use ExUnit.Case
  alias Membrane.AAC.Filler
  alias Membrane.Buffer

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
               assert buffer.payload == Filler.silent_frame()
             end)
    end
  end
end
