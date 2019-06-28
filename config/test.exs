use Mix.Config

config :k8s,
  # discovery_provider: Mock.Discovery,
  http_provider: K8s.Client.DynamicHTTPProvider,
  clusters: %{
    test: %{
      conf: "test/support/kube-config.yaml"
    }
  }
