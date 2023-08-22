defmodule Membrane.AAC.Parser.Esds do
  @moduledoc """
  Utility functions for parsing and generating `esds` atom.

  It's structure is defined in ISO/IEC 14496-1.
  """

  alias Membrane.AAC

  @spec generate_esds(AAC.t(), Membrane.Element.state()) :: binary()
  def generate_esds(stream_format, state) do
    aot_id = Membrane.AAC.profile_to_aot_id(stream_format.profile)
    frequency_id = Membrane.AAC.sample_rate_to_sampling_frequency_id(stream_format.sample_rate)
    channel_config_id = Membrane.AAC.channels_to_channel_config_id(stream_format.channels)

    frame_length_id =
      Membrane.AAC.samples_per_frame_to_frame_length_id(stream_format.samples_per_frame)

    depends_on_core_coder = 0
    extension_flag = 0

    custom_frequency = if frequency_id == 15, do: <<stream_format.sample_rate::24>>, else: <<>>

    section5 =
      <<aot_id::5, frequency_id::4, custom_frequency::binary, channel_config_id::4,
        frame_length_id::1, depends_on_core_coder::1, extension_flag::1>>
      |> generate_esds_section(5)

    # 64 = mpeg4-audio
    object_type_id = 64
    # 5 = audio
    stream_type = 5
    upstream_flag = 0
    reserved_flag_set_to_1 = 1
    buffer_size = 0

    section4 =
      <<object_type_id, stream_type::6, upstream_flag::1, reserved_flag_set_to_1::1,
        buffer_size::24, state.max_bit_rate::32, state.avg_bit_rate::32, section5::binary>>
      |> generate_esds_section(4)

    section6 = <<2>> |> generate_esds_section(6)

    elementary_stream_id = 1
    stream_priority = 0

    <<elementary_stream_id::16, stream_priority, section4::binary, section6::binary>>
    |> generate_esds_section(3)
  end

  defp generate_esds_section(payload, section_no) do
    type_tag = <<128, 128, 128>>
    <<section_no, type_tag::binary, byte_size(payload), payload::binary>>
  end

  @spec parse_esds(binary()) :: %{
    profile: AAC.profile(),
    samples_per_frame: AAC.samples_per_frame()
  }
  def parse_esds(esds) do
  stream_priority = 0

  {esds, <<>>} = unpack_esds_section(esds, 3)
  <<_elementary_stream_id::16, ^stream_priority, rest::binary>> = esds

  {section_4, esds_section_6} = unpack_esds_section(rest, 4)
  {<<2>>, <<>>} = unpack_esds_section(esds_section_6, 6)

  # 64 = mpeg4-audio
  object_type_id = 64
  # 5 = audio
  stream_type = 5
  upstream_flag = 0
  reserved_flag_set_to_1 = 1
  buffer_size = 0

  <<^object_type_id, ^stream_type::6, ^upstream_flag::1, ^reserved_flag_set_to_1::1,
  ^buffer_size::24, _max_bit_rate::32, _avg_bit_rate::32, esds_section_5::binary>> = section_4

  {section_5, <<>>} = unpack_esds_section(esds_section_5, 5)

  depends_on_core_coder = 0
  extension_flag = 0

  <<aot_id::5, frequency_id::4, section_5_rest::bitstring>> = section_5

  custom_frequency_length = if frequency_id == 15, do: 24, else: 0

  <<_maybe_custom_frequency::integer-size(custom_frequency_length), _channel_config_id::4,
  frame_length_id::1, ^depends_on_core_coder::1, ^extension_flag::1>> = section_5_rest

  %{
  profile: AAC.aot_id_to_profile(aot_id),
  samples_per_frame: AAC.frame_length_id_to_samples_per_frame(frame_length_id)
  }
  end

  defp unpack_esds_section(section, section_no) do
    type_tag = <<128, 128, 128>>

    <<^section_no::8-integer, ^type_tag::binary-size(3), payload_size::8-integer, rest::binary>> =
      section

    <<payload::binary-size(payload_size), rest::binary>> = rest
    {payload, rest}
  end
end
