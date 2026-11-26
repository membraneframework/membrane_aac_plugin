defmodule Membrane.AAC.Parser.AudioSpecificConfigTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Membrane.AAC
  alias Membrane.AAC.Parser.AudioSpecificConfig

  # AAC Low Complexity, 44 100 Hz, stereo, 1024 samples per frame
  @lc_config <<2::5, 4::4, 2::4, 0::3>>

  describe "parse/1" do
    test "parses a config" do
      assert {:ok,
              %AAC{
                profile: :LC,
                mpeg_version: 4,
                sample_rate: 44_100,
                channels: 2,
                samples_per_frame: 1024,
                encapsulation: :none,
                config: {:audio_specific_config, @lc_config}
              }} = AudioSpecificConfig.parse(@lc_config)
    end

    test "parses a config with an explicit sampling frequency" do
      config = <<2::5, 15::4, 12_345::24, 1::4, 1::1, 0::2>>

      assert {:ok, %AAC{sample_rate: 12_345, channels: 1, samples_per_frame: 960}} =
               AudioSpecificConfig.parse(config)
    end

    test "leaves the channels unset when the config does not give their number" do
      assert {:ok, %AAC{channels: nil}} = AudioSpecificConfig.parse(<<2::5, 4::4, 0::4, 0::3>>)
    end

    test "returns an error for a config that is too short" do
      assert {:error, :too_short} == AudioSpecificConfig.parse(<<>>)
      assert {:error, :too_short} == AudioSpecificConfig.parse(<<2::5, 4::3>>)
      assert {:error, :too_short} == AudioSpecificConfig.parse(<<2::5, 15::4, 12_345::23>>)
    end

    test "returns an error for an audio object type that Membrane.AAC does not have" do
      # 23 is AAC Low Delay
      assert {:error, {:unsupported_audio_object_type_id, 23}} ==
               AudioSpecificConfig.parse(<<23::5, 4::4, 2::4, 0::3>>)
    end

    test "returns an error for a reserved sampling frequency id" do
      assert {:error, {:unsupported_sampling_frequency_id, 13}} ==
               AudioSpecificConfig.parse(<<2::5, 13::4, 2::4, 0::3>>)
    end

    test "returns an error for a reserved channel configuration" do
      assert {:error, {:unsupported_channel_config_id, 8}} ==
               AudioSpecificConfig.parse(<<2::5, 4::4, 8::4, 0::3>>)
    end

    test "does not raise on any config of two bytes" do
      Enum.each(0..0xFFFF, fn config ->
        assert {result, _stream_format_or_reason} = AudioSpecificConfig.parse(<<config::16>>)
        assert result in [:ok, :error]
      end)
    end
  end

  describe "parse_audio_specific_config/1" do
    test "returns the stream format" do
      assert {:ok, AudioSpecificConfig.parse_audio_specific_config(@lc_config)} ==
               AudioSpecificConfig.parse(@lc_config)
    end

    test "raises on a config that cannot be parsed" do
      assert_raise RuntimeError, ~r/unsupported_audio_object_type_id, 23/, fn ->
        AudioSpecificConfig.parse_audio_specific_config(<<23::5, 4::4, 2::4, 0::3>>)
      end
    end
  end
end
