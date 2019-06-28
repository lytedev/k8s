defmodule K8s.Discovery do
  @moduledoc """
  Auto discovery of Kubenetes API Versions and Groups.
  """

  @behaviour K8s.Behaviours.DiscoveryProvider

  alias K8s.Cluster
  alias K8s.Conf.RequestOptions

  @doc "List all resource definitions by group"
  @impl true
  def resource_definitions_by_group(cluster_name, opts \\ []) do
    {:ok, conf} = Cluster.conf(cluster_name)
    timeout = K8s.Config.discovery_http_timeout(cluster_name)

    cluster_name
    |> api_paths(opts)
    |> Enum.into(%{})
    |> Enum.reduce([], fn {prefix, versions}, acc ->
      versions
      |> Enum.map(&async_get_resource_definition(prefix, &1, conf, opts))
      |> Enum.concat(acc)
    end)
    |> Enum.map(fn task -> Task.await(task, timeout) end)
    |> List.flatten()
  end

  @doc "Get a map of API type to groups"
  @spec api_paths(atom, keyword) :: map | {:error, binary | atom}
  def api_paths(cluster_name, defaults \\ []) do
    {:ok, conf} = Cluster.conf(cluster_name)
    timeout = K8s.Config.discovery_http_timeout(cluster_name)
    api_url = "#{conf.url}/api/"
    apis_url = "#{conf.url}/apis/"
    opts = Keyword.merge([recv_timeout: timeout], defaults)

    with {:ok, api} <- do_run(api_url, conf, opts),
         {:ok, apis} <- do_run(apis_url, conf, opts) do
      %{
        "/api/" => api["versions"],
        "/apis/" => group_versions(apis["groups"])
      }
    else
      error -> error
    end
  end

  @doc """
  Asynchronously fetch resource definitions.

  `Task` will contain a list of resource definitions.

  In the event of failure an empty list is returned.
  """
  @spec async_get_resource_definition(binary, binary, map, keyword) :: %Task{}
  def async_get_resource_definition(prefix, version, conf, opts) do
    Task.async(fn ->
      url = Path.join([conf.url, prefix, version])

      case do_run(url, conf, opts) do
        {:ok, resource_definition} ->
          resource_definition

        _ ->
          []
      end
    end)
  end

  defp group_versions(groups) do
    Enum.reduce(groups, [], fn group, acc ->
      group_versions = Enum.map(group["versions"], fn %{"groupVersion" => gv} -> gv end)
      acc ++ group_versions
    end)
  end

  defp do_run(url, conf, opts) do
    case RequestOptions.generate(conf) do
      {:ok, request_options} ->
        headers = K8s.http_provider().headers(request_options)
        opts = Keyword.merge([ssl: request_options.ssl_options], opts)

        IO.puts("URL: #{url}")
        {:ok, resp} = K8s.http_provider().request(:get, url, "", headers, opts)
        IO.puts("Body: #{inspect(resp)}")

      error ->
        error
    end
  end
end
