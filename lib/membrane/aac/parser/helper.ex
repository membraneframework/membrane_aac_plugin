defmodule Membrane.AAC.Parser.Helper do
  @moduledoc false
  use Bunch
  alias Membrane.{AAC, Buffer}

  @header_size 7
  @crc_size 2

  @spec parse_adts(binary, AAC.t(), %{samples_per_frame: 1024 | 960}) ::
          {:ok, {[{:caps, AAC.t()} | {:buffer, Buffer.t()}], binary}} | {:error, :adts_header}
  def parse_adts(data, caps, options) do
    with {:ok, {output, rest}} <-
           Bunch.List.try_unfoldr({data, caps}, &do_parse_adts(&1, options)) do
      {:ok, {List.flatten(output), rest}}
    end
  end

  defp do_parse_adts({data, caps}, options) when byte_size(data) > @header_size + @crc_size do
    withl header: {:ok, frame_caps, header, crc, frame_length} <- parse_header(data, options),
          header: :ok <- verify_header(header, crc),
          payload: <<frame::binary-size(frame_length), rest::binary>> <- data do
      caps = if caps == frame_caps, do: [], else: [caps: frame_caps]
      {:ok, {:cont, caps ++ [buffer: %Buffer{payload: frame}], {rest, frame_caps}}}
    else
      header: :error -> {:error, :adts_header}
      payload: rest -> {:ok, {:halt, rest}}
    end
  end

  defp do_parse_adts({data, _caps}, _options), do: {:ok, {:halt, data}}

  defp parse_header(
         <<0xFFF::12, _version::1, 0::2, protection_absent::1, profile_id::2,
           sampling_frequency_id::4, _priv_bit::1, channel_config_id::3, _::4, frame_length::13,
           _buffer_fullness::11, aac_frames_cnt::2, rest::binary>> = data,
         options
       )
       when sampling_frequency_id <= 12 do
    <<header::binary-size(@header_size), ^rest::binary>> = data

    crc =
      if protection_absent == 1 do
        <<>>
      else
        <<crc::16, _rest::binary>> = rest
        crc
      end

    caps = %AAC{
      profile: AAC.aot_id_to_profile(profile_id + 1),
      sample_rate: AAC.sampling_frequency_id_to_sample_rate(sampling_frequency_id),
      channels: AAC.channel_config_id_to_channels(channel_config_id),
      frames_per_buffer: aac_frames_cnt + 1,
      samples_per_frame: options.samples_per_frame,
      encapsulation: :adts
    }

    {:ok, caps, header, crc, frame_length}
  end

  defp parse_header(_payload, _options), do: :error

  defp verify_header(_header, <<>>), do: :ok

  defp verify_header(header, crc) do
    if crc == CRC.crc_16(header), do: :ok, else: :error
  end
end
