defmodule ExAws.Dynamo.Impl do
  import ExAws.Dynamo.Request
  alias ExAws.Dynamo
  use ExAws.Actions

  @namespace "DynamoDB_20120810"
  @actions [
    batch_get_item:   :get,
    batch_write_item: :post,
    create_table:     :post,
    delete_item:      :post,
    delete_table:     :post,
    describe_table:   :get,
    get_item:         :get,
    list_tables:      :get,
    put_item:         :post,
    query:            :get,
    scan:             :get,
    update_item:      :post,
    update_table:     :post]

  @moduledoc "See ExAws.Dynamo.Adapter for documentation"

  ## Tables
  ######################

  def list_tables(adapter) do
    request(%{}, :list_tables, adapter)
  end

  def create_table(adapter, name, primary_key, key_definitions, read_capacity, write_capacity) do
    key_schema = [%{
      AttributeName: primary_key,
      KeyType: "HASH"
    }]
    create_table(adapter, name, key_schema, key_definitions, read_capacity, write_capacity, [], [])
  end

  def create_table(adapter, name, key_schema, key_definitions, read_capacity, write_capacity, global_indexes, local_indexes) do
    data = %{
      TableName: name,
      AttributeDefinitions: key_definitions |> encode_attrs,
      KeySchema: key_schema,
      ProvisionedThroughput: %{
        ReadCapacityUnits: read_capacity,
        WriteCapacityUnits: write_capacity
      }
    }
    [GlobalSecondaryIndexes: global_indexes, LocalSecondaryIndexes: local_indexes]
    |> Enum.reduce(data, fn
      {_, []}, data -> data
      {name, indices}, data -> Map.put(data, name, Enum.into(indices, %{}))
    end)
    |> request(:create_table, adapter)
  end

  @doc "Describe table"
  def describe_table(adapter, name) do
    %{TableName: name}
    |> request(:describe_table, adapter)
  end

  @doc "Update Table"
  def update_table(adapter, name, attributes) do
    %{TableName: name}
    |> Map.merge(attributes)
    |> request(:update_table, adapter)
  end

  def delete_table(adapter, table) do
    %{TableName: table}
    |> request(:delete_table, adapter)
  end

  ## Records
  ######################

  def scan(adapter, name, opts) do
    %{TableName: name}
    |> Map.merge(opts)
    |> request(:scan, adapter)
  end

  def query(adapter, name, key_conditions, opts) do
    %{TableName: name, KeyConditions: key_conditions}
    |> Map.merge(opts)
    |> request(:query, adapter)
  end

  def batch_get_item(adapter, data) do
    request(data, :batch_get_item, adapter)
  end

  def put_item(adapter, name, record) do
    %{
      TableName: name,
      Item: Dynamo.Encoder.encode(record)
    } |> request(:put_item, adapter)
  end

  def batch_write_item(adapter, data) do
    request(data, :batch_write_item, adapter)
  end

  def get_item(adapter, name, primary_key) do
    %{
      TableName: name,
      Key: Dynamo.Encoder.encode_flat(primary_key)
    }
    |> request(:get_item, adapter)
  end

  def update_item(adapter, table_name, primary_key, update_args) do
    %{
      TableName: table_name,
      Key: Dynamo.Encoder.encode_flat(primary_key)
    }
    |> Map.merge(update_args)
    |> request(:update_item, adapter)
  end

  def delete_item(adapter, name, primary_key) do
    %{TableName: name, Key: primary_key}
    |> request(:delete_item, adapter)
  end

  defp encode_attrs(attrs) do
    attrs |> Enum.map(fn({name, type}) ->
      %{AttributeName: name, AttributeType: type}
    end)
  end
end