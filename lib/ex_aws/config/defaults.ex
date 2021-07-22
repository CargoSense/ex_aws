defmodule ExAws.Config.Defaults do
  @moduledoc """
  Defaults for each service
  """

  @common %{
    access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
    secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
    http_client: ExAws.Request.Hackney,
    json_codec: Jason,
    retries: [
      max_attempts: 10,
      base_backoff_in_ms: 10,
      max_backoff_in_ms: 10_000
    ],
    normalize_path: true
  }

  @doc """
  Retrieve the default configuration for a service.
  """
  def defaults(:dynamodb_streams) do
    %{service_override: :dynamodb}
    |> Map.merge(defaults(:dynamodb))
  end

  def defaults(:lex_runtime) do
    %{service_override: :lex}
    |> Map.merge(defaults(:lex))
  end

  def defaults(:lex_models) do
    %{service_override: :lex}
    |> Map.merge(defaults(:lex))
  end

  def defaults(:sagemaker_runtime) do
    %{service_override: :sagemaker}
    |> Map.merge(defaults(:sagemaker))
  end

  def defaults(:iot_data) do
    %{service_override: :iotdata}
    |> Map.merge(defaults(:iot))
  end

  def defaults(:"session.qldb") do
    %{service_override: :qldb}
    |> Map.merge(defaults(:qldb))
  end

  def defaults(:ingest_timestream) do
    %{service_override: :timestream}
    |> Map.merge(defaults(:timestream))
  end

  def defaults(:query_timestream) do
    %{service_override: :timestream}
    |> Map.merge(defaults(:timestream))
  end

  def defaults(_) do
    Map.merge(
      %{
        scheme: "https://",
        region: "us-east-1",
        port: 443
      },
      @common
    )
  end

  def get(service, region) do
    service
    |> defaults
    |> Map.put(:host, host(service, region))
  end

  @partitions [
    {~r/^(us|eu|af|ap|sa|ca|me)\-(east|west|south|north|northeast|southeast|central)\-\d+$/,
     "aws"},
    {~r/^cn\-\w+\-\d+$/, "aws-cn"},
    {~r/^us\-gov\-\w+\-\d+$/, "aws-us-gov"}
  ]

  def host(service, region) do
    partition =
      Enum.find(@partitions, fn {regex, _} ->
        Regex.run(regex, region)
      end)

    with {_, partition} <- partition do
      do_host(partition, service, region)
    end
  end

  defp service_map(:ses), do: "email"
  defp service_map(:sagemaker_runtime), do: "runtime.sagemaker"
  defp service_map(:lex_runtime), do: "runtime.lex"
  defp service_map(:lex_models), do: "models.lex"
  defp service_map(:dynamodb_streams), do: "streams.dynamodb"
  defp service_map(:iot_data), do: "data.iot"
  defp service_map(:ingest_timestream), do: "ingest.timestream"
  defp service_map(:query_timestream), do: "query.timestream"

  defp service_map(service) do
    service
    |> to_string
    |> String.replace("_", "-")
  end

  @external_resource "priv/endpoints.exs"

  @partition_data Code.eval_file("priv/endpoints.exs", File.cwd!())
                  |> elem(0)
                  |> Map.get("partitions")
                  |> Map.new(fn partition ->
                    {partition["partition"], partition}
                  end)

  defp do_host(partition, service_slug, region) do
    partition = @partition_data |> Map.fetch!(partition)
    partition_name = partition["partition"]

    service = service_map(service_slug)

    partition
    |> Map.fetch!("services")
    |> fetch_or(service, "#{service_slug} not found in partition #{partition_name}")
    |> case do
      %{"isRegionalized" => false} = data ->
        data
        |> Map.fetch!("endpoints")
        |> Map.values()
        |> List.first()

      data ->
        data
        |> Map.fetch!("endpoints")
        |> fetch_or(
          region,
          "#{service_slug} not supported in region #{region} for partition #{partition_name}"
        )
    end
    |> case do
      %{"hostname" => hostname} ->
        hostname

      _ ->
        dns_suffix = Map.fetch!(partition, "dnsSuffix")
        hostname = Map.fetch!(partition, "defaults") |> Map.fetch!("hostname")
        apply_defaults(hostname, service, region, dns_suffix)
    end
  end

  defp fetch_or(map, key, msg) do
    Map.get(map, key) || raise msg
  end

  def apply_defaults(hostname, service, region, dns_suffix) do
    hostname
    |> String.replace("{service}", service)
    |> String.replace("{region}", region)
    |> String.replace("{dnsSuffix}", dns_suffix)
  end
end
