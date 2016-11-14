defmodule ExAws.SNS.PublicKeyCache do
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def get(cert_url) do
      case :ets.lookup(__MODULE__, cert_url) do
        [{cert_url, public_key}] -> {:ok, public_key}
        [] -> GenServer.call(__MODULE__, {:get_public_key, cert_url})
    end
  end

  ## Callbacks

  def init(:ok) do
    ets = :ets.new(__MODULE__, [:named_table, read_concurrency: true])
    {:ok, ets}
  end

  def handle_call({:get_public_key, cert_url}, _from, ets) do
    with {:ok, cert} <- fetch_certificate(cert_url),
         public_key  <- get_public_key(cert) do
      :ets.insert(__MODULE__, {cert_url, public_key})
      {:reply, {:ok, public_key}, ets}
    else
      error -> {:reply, error, ets}
    end
  end

  defp fetch_certificate(cert_url) do
    with {:ok, 200, _resp_headers, cert_binary} <- :hackney.get(cert_url, [], "", [:with_body]) do
      get_pem_entry(:public_key.pem_decode(cert_binary))  
    else
      {:ok, status_code, _resp_headers, _client} -> {:error, "Could not fetch certificate from #{cert_url}, expected http code 200, got: #{status_code}"}
      {:error, error} -> {:error, "Unexpected error, could not fetch certificate from #{cert_url}, got #{inspect error}"}
    end
  end

  defp get_pem_entry(pem_entries) do
    case pem_entries do
      [entry] -> 
        try do
          {:ok, :public_key.pem_entry_decode(Enum.at(pem_entries, 0))}
        catch
          kind, error -> {:error, "Unexpected error while decoding pem entry: #{inspect error}"}
        end
      entries -> 
        {:error, "Invalid PEM entries: #{inspect entries}"}
    end
  end  
  
  defp get_public_key(cert) do
    :public_key.der_decode(:RSAPublicKey, cert |> elem(1) |> elem(7) |> elem(2))
  end

end