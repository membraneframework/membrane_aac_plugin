defmodule Membrane.AAC.Parser.EsdsTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Membrane.AAC
  alias Membrane.AAC.Parser.Esds

  describe "parse_esds/1" do
    test "tolerates a DecoderConfigDescriptor whose reserved bit is 0" do
      # Real esds captured from an MP4 whose encoder leaves the
      # DecoderConfigDescriptor "reserved" bit cleared: the second byte is
      # 0x14 (stream_type 5, upstream 0, reserved 0) instead of the
      # spec-mandated 0x15. ISO/IEC 14496-1 says the bit "should" be 1, but
      # many encoders emit 0 and a parser must not crash on otherwise-valid
      # streams.
      section_4 =
        <<64, 0x14, 0, 24, 0, 0, 1, 244, 0, 0, 1, 244, 0, 5, 128, 128, 128, 2, 0x11, 0x90>>

      section_4_wrapped = <<4, 128, 128, 128, byte_size(section_4), section_4::binary>>
      section_6 = <<6, 128, 128, 128, 1, 2>>
      section_3_payload = <<1::16, 0, section_4_wrapped::binary, section_6::binary>>
      esds = <<3, 128, 128, 128, byte_size(section_3_payload), section_3_payload::binary>>

      assert %AAC{profile: :LC, sample_rate: 48_000, channels: 2} = Esds.parse_esds(esds)
    end

    test "parses a DecoderConfigDescriptor whose reserved bit is the conformant 1" do
      section_4 =
        <<64, 0x15, 0, 24, 0, 0, 1, 244, 0, 0, 1, 244, 0, 5, 128, 128, 128, 2, 0x11, 0x90>>

      section_4_wrapped = <<4, 128, 128, 128, byte_size(section_4), section_4::binary>>
      section_6 = <<6, 128, 128, 128, 1, 2>>
      section_3_payload = <<1::16, 0, section_4_wrapped::binary, section_6::binary>>
      esds = <<3, 128, 128, 128, byte_size(section_3_payload), section_3_payload::binary>>

      assert %AAC{profile: :LC, sample_rate: 48_000, channels: 2} = Esds.parse_esds(esds)
    end
  end
end
