defmodule ExAws.InstanceMeta do
  @moduledoc false

  # Provides access to the AWS Instance MetaData
  # http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html

  # AWS InstanceMetaData URL
  @meta_path_root "http://169.254.169.254/latest/meta-data"

  # Endpoint for ECS tasks role credentials
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html
  @task_role_root "http://169.254.170.2"

  def request(config, url) do
    # If we're using IMDSv2, we will need to pass in session token headers.
    headers = get_request_headers(config)

    case config.http_client.request(:get, url, "", headers, http_opts()) do
      {:ok, %{status_code: 200, body: body}} ->
        body

      {:ok, %{status_code: status_code}} ->
        raise """
        Instance Meta Error: HTTP response status code #{inspect(status_code)}

        Please check AWS EC2 IAM role.
        """

      error ->
        raise """
        Instance Meta Error: #{inspect(error)}

        You tried to access the AWS EC2 instance meta, but it could not be reached.
        This happens most often when trying to access it from your local computer,
        which happens when environment variables are not set correctly prompting
        ExAws to fallback to the Instance Meta.

        Please check your key config and make sure they're configured correctly:

        For Example:
        ```
        ExAws.Config.new(:s3)
        ExAws.Config.new(:dynamodb)
        ```
        """
    end
  end

  def get_request_headers(config) do
    # TODO: Make this conditional on something in config
    ExAws.InstanceMetaTokenProvider.get_headers(config)
  end

  def instance_role(config) do
    ExAws.InstanceMeta.request(config, @meta_path_root <> "/iam/security-credentials/")
  end

  def task_role_credentials(config) do
    case System.get_env("AWS_CONTAINER_CREDENTIALS_RELATIVE_URI") do
      nil ->
        nil

      uri ->
        ExAws.InstanceMeta.request(config, @task_role_root <> uri)
        |> config.json_codec.decode!
    end
  end

  def instance_role_credentials(config) do
    ExAws.InstanceMeta.request(
      config,
      @meta_path_root <> "/iam/security-credentials/#{instance_role(config)}"
    )
    |> config.json_codec.decode!
  end

  def security_credentials(config) do
    result =
      case task_role_credentials(config) do
        nil -> instance_role_credentials(config)
        credentials -> credentials
      end

    %{
      access_key_id: result["AccessKeyId"],
      secret_access_key: result["SecretAccessKey"],
      security_token: result["Token"],
      expiration: result["Expiration"]
    }
  end

  defp http_opts do
    # Certain solutions like kube2iam will redirect instance meta requests,
    # we need to follow those redirects.
    defaults = [follow_redirect: true]

    overrides =
      Application.get_env(:ex_aws, :metadata, [])
      |> Keyword.get(:http_opts, [])

    Keyword.merge(defaults, overrides)
  end
end
