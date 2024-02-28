defmodule Membrane.AAC.Parser.LATM do
  @moduledoc """
  Utility functions for parsing and generating LATM encapsulation structures.


  """

  use Bunch
  alias Membrane.{AAC, Buffer}
  alias Membrane.AAC.Parser.Config
  # use sth like __PARENT_MODULE__ instead __jm__ to be consistent with parser.ex
  alias Membrane.AAC.Parser.Utils

  @spec parse_latm(binary, AAC.t() | nil, AAC.Parser.timestamp(), Membrane.Element.state()) ::
          {:ok, {[parse_action()], binary, AAC.Parser.timestamp()}}
          | {:error, any()}
  def parse_latm(data, stream_format, timestamp, state) do
    raise "__jm__"
  end

  @spec do_parse_latm(any(), Membrane.Element.state()) ::
          {:ok, {:cont, parse_result(), any()} | {:halt, any()}} | {:error, any()}
  defp do_parse_latm({data, stream_format, timestamp}, state) do
    raise "__jm__"
  end

  defp do_parse_latm({data, _stream_format, timestamp}, _options),
    do: {:ok, {:halt, {data, timestamp}}}

  defp parse_header(_payload, _options), do: raise("__jm__")

  # defp extract_frame(data, _adts_size, size, %{out_encapsulation: :ADTS}) do
  #   case data do
  #     <<frame::binary-size(size), rest::binary>> -> {:frame, frame, rest}
  #     _other -> :no_frame
  #   end
  # end

  # defp extract_frame(data, adts_size, size, %{out_encapsulation: :none}) do
  #   frame_size = size - adts_size

  #   case data do
  #     <<_adts::binary-size(adts_size), frame::binary-size(frame_size), rest::binary>> ->
  #       {:frame, frame, rest}

  #     _other ->
  #       :no_frame
  #   end
  # end

  @spec payload_to_latm(binary(), AAC.t()) :: binary()
  def payload_to_latm(payload, %AAC{} = stream_format) do
    header = raise "__jm__"
    header <> payload
  end
end
