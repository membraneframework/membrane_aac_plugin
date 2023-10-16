defmodule Membrane.AAC.Parser.Esds do
  @moduledoc """
  Utility functions for parsing and generating `esds` atom.

  It's structure is defined in ISO/IEC 14496-1.
  """

  alias Membrane.AAC
  alias Membrane.AAC.Parser.AudioSpecificConfig

  @spec generate_esds(AAC.t(), Membrane.Element.state()) :: binary()
  def generate_esds(stream_format, state) do
    section5 =
      generate_esds_section(AudioSpecificConfig.generate_audio_specific_config(stream_format), 5)

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

  @spec parse_esds(binary()) :: AAC.t()
  def parse_esds(esds) do
    {section_3, <<>>} = unpack_esds_section(esds, 3)

    <<_elementary_stream_id::16, stream_dependence_flag::1, url_flag::1, ocr_stream_flag::1,
      _stream_priority::5,
      rest::binary>> =
      section_3

    rest =
      rest
      |> Bunch.then_if(stream_dependence_flag != 0, fn binary ->
        <<_depends_on_es_id::16, rest::binary>> = binary
        rest
      end)
      |> Bunch.then_if(url_flag != 0, fn binary ->
        <<url_length::8, rest::binary>> = binary
        <<_url::binary-size(url_length), rest::binary>> = rest
        rest
      end)
      |> Bunch.then_if(ocr_stream_flag != 0, fn binary ->
        <<_ocr_es_id::16, rest::binary>> = binary
        rest
      end)

    {section_4, esds_section_6} = unpack_esds_section(rest, 4)
    {<<2>>, <<>>} = unpack_esds_section(esds_section_6, 6)

    # 64 = mpeg4-audio
    object_type_id = 64
    # 5 = audio
    stream_type = 5
    upstream_flag = 0
    reserved_flag_set_to_1 = 1

    <<^object_type_id, ^stream_type::6, ^upstream_flag::1, ^reserved_flag_set_to_1::1,
      _buffer_size::24, _max_bit_rate::32, _avg_bit_rate::32, esds_section_5::binary>> = section_4

    {section_5, <<>>} = unpack_esds_section(esds_section_5, 5)

    AudioSpecificConfig.parse_audio_specific_config(section_5)
    |> Map.put(:config, {:esds, esds})
  end

  defp unpack_esds_section(section, section_no) do
    type_tag = <<128, 128, 128>>

    case section do
      <<^section_no::8-integer, ^type_tag::binary-size(3), payload_size::8-integer, rest::binary>> ->
        <<payload::binary-size(payload_size), rest::binary>> = rest
        {payload, rest}

      <<^section_no::8-integer, payload_size::8-integer, rest::binary>> ->
        <<payload::binary-size(payload_size), rest::binary>> = rest
        {payload, rest}
    end
  end
end
