defmodule ExAws.Request.Url do
  @moduledoc false

  @doc """
  Builds URL for an operation and a config"
  """
  def build(operation, config) do
    config
    |> Map.take([:scheme, :host, :port])
    |> Map.put(:query, query(operation))
    |> Map.put(:path, operation.path)
    |> normalize_scheme
    |> normalize_path(config.normalize_path)
    |> convert_port_to_integer
    |> (&struct(URI, &1)).()
    |> URI.to_string()
    |> String.trim_trailing("?")
  end

  defp query(operation) do
    operation
    |> Map.get(:params, %{})
    |> normalize_params
    |> URI.encode_query()
  end

  defp normalize_scheme(url) do
    url |> Map.update(:scheme, "", &String.replace(&1, "://", ""))
  end

  defp normalize_path(url, false), do: url

  defp normalize_path(url, _normalize) do
    url |> Map.update(:path, "", &String.replace(&1, ~r/\/{2,}/, "/"))
  end

  defp convert_port_to_integer(url = %{port: port}) when is_binary(port) do
    {port, _} = Integer.parse(port)
    put_in(url[:port], port)
  end

  defp convert_port_to_integer(url), do: url

  defp normalize_params(params) when is_map(params) do
    params |> Map.delete("") |> Map.delete(nil)
  end

  defp normalize_params(params), do: params

  def sanitize(url, service) when service in ["s3", :s3] do
    new_path =
      url
      |> get_path(service)
      |> String.replace_prefix("/", "")
      |> uri_encode()

    query =
      case String.split(url, "?", parts: 2) do
        [_] -> nil
        [_, ""] -> nil
        [_, q] -> q
      end

    url
    |> URI.parse()
    |> Map.put(:fragment, nil)
    |> Map.put(:path, "/" <> new_path)
    |> Map.put(:query, query_replace_spaces(query))
    |> URI.to_string()
  end

  def sanitize(url, _), do: String.replace(url, "+", "%20")

  def get_path(url, service \\ nil)
  # Elixir's URI.parse will treat everything after the # sign
  # as a fragment. This is correct, but S3 treats it as part
  # of the path of the object.
  #
  # This will split the URL at the base with the right side
  # being the path, except for the query params.
  #
  # for example:
  # `"https://bucket.aws.com/my/path/here+ #3.txt?t=21"`
  # https://bucket.aws.com | /my/path/here+ #3.txt?t=21
  # ________base__________ | /my/path/here+ #3.txt | t=21
  # ________base__________ | /my/path/here+ #3.txt | _params_
  #
  # After using `uri_encode` it will be `/my/path/here%2B%20%233.txt`
  #
  def get_path(url, service) when service in ["s3", :s3] do
    base =
      url
      |> URI.parse()
      |> Map.put(:path, nil)
      |> Map.put(:query, nil)
      |> Map.put(:fragment, nil)
      |> URI.to_string()

    [_base, path_with_params] = String.split(url, base, parts: 2)
    [path | _query_params] = String.split(path_with_params, "?", parts: 2)

    path
  end

  def get_path(url, _), do: URI.parse(url).path

  def uri_encode(url), do: URI.encode(url, &valid_path_char?/1)

  defp query_replace_spaces(nil), do: nil
  defp query_replace_spaces(query), do: String.replace(query, "+", "%20")

  # Space character
  defp valid_path_char?(?\ ), do: false
  defp valid_path_char?(?/), do: true

  defp valid_path_char?(c) do
    URI.char_unescaped?(c) && !URI.char_reserved?(c)
  end
end
