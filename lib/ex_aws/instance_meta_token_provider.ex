defmodule ExAws.InstanceMetaTokenProvider do
  @moduledoc """
  For use with IMDSv2, this module retrieves the metadata session token and refreshes it before expiration.
  """

  # 6 hours
  @metadata_token_ttl_seconds 6 * 60 * 60
  @genserver_call_timeout_seconds 30
  @metadata_token_api_url "http://169.254.169.254/latest/api/token"
  # The header we pass to control the token's time to live
  @metadata_token_ttl_header_name "x-aws-ec2-metadata-token-ttl-seconds"
  # The header we use to pass the token along to all other metadata calls
  @metadata_token_header_name "x-aws-ec2-metadata-token"

  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def get(config) do
    case :ets.lookup(__MODULE__, :aws_metadata_token) do
      [{:aws_metadata_token, token}] ->
        token

      [] ->
        GenServer.call(
          __MODULE__,
          {:refresh_token, config},
          @genserver_call_timeout_seconds * 1_000
        )
    end
  end

  def get_headers(config) do
    [{@metadata_token_header_name, get(config)}]
  end

  ## Callbacks

  def init(:ok) do
    ets = :ets.new(__MODULE__, [:named_table, read_concurrency: true])
    {:ok, ets}
  end

  def handle_call({:refresh_token, config}, _from, ets) do
    token = refresh_token(config, ets)
    {:reply, token, ets}
  end

  def handle_info({:refresh_token, config}, ets) do
    refresh_token(config, ets)
    {:noreply, ets}
  end

  def refresh_token(config, ets) do
    token = request_token(config)
    :ets.insert(ets, {:aws_metadata_token, token})
    Process.send_after(self(), {:refresh_token, config}, refresh_in(config))
    token
  end

  # TODO: Allow overriding defaults in config
  def refresh_in(_config) do
    # Check five minutes prior to expiration, or now, which ever is later.
    refresh_in = @metadata_token_ttl_seconds - 5 * 60
    max(0, refresh_in * 1_000)
  end

  def request_token(config) do
    case config.http_client.request(
           :put,
           @metadata_token_api_url,
           "",
           token_ttl_seconds_headers(config),
           follow_redirect: true
         ) do
      {:ok, %{status_code: 200, body: body}} ->
        body

      {:ok, %{status_code: status_code}} ->
        raise """
        Instance Meta Error: HTTP response status code #{inspect(status_code)}

        Please check AWS EC2 Instance Metadata Service configuration to make sure the service is configured properly.
        """

      error ->
        raise """
        Instance Meta Error: #{inspect(error)}

        You tried to access the AWS EC2 Instance Metadata token API, but it could not be reached.

        Please check AWS EC2 Instance Metadata Service configuration to make sure the service is enabled.
        """
    end
  end

  # TODO: Allow overriding defaults in config
  defp token_ttl_seconds_headers(_config) do
    [{@metadata_token_ttl_header_name, @metadata_token_ttl_seconds}]
  end
end
