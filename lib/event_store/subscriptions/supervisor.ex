defmodule EventStore.Subscriptions.Supervisor do
  @moduledoc false

  # Supervise zero, one or more subscriptions to an event stream.

  use Supervisor

  alias EventStore.Subscriptions.Subscription

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def subscribe_to_stream(stream_uuid, subscription_name, subscriber, subscription_opts) do
    name = {:via, Registry, registry_name(stream_uuid, subscription_name)}

    Supervisor.start_child(__MODULE__, [
      stream_uuid,
      subscription_name,
      subscriber,
      subscription_opts,
      [name: name]
    ])
  end

  def unsubscribe_from_stream(stream_uuid, subscription_name) do
    name = registry_name(stream_uuid, subscription_name)

    case Registry.whereis_name(name) do
      :undefined ->
        :ok

      subscription ->
        :ok = Subscription.unsubscribe(subscription)
        :ok = Supervisor.terminate_child(__MODULE__, subscription)
    end
  end

  def reconnect do
    for {_id, subscription, _type, _modules} <- Supervisor.which_children(__MODULE__) do
      Subscription.reconnect(subscription)
    end
  end

  def disconnect do
    for {_id, subscription, _type, _modules} <- Supervisor.which_children(__MODULE__) do
      Subscription.disconnect(subscription)
    end
  end

  def init(args) do
    children = [
      worker(Subscription, args, restart: :temporary)
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  defp registry_name(stream_uuid, subscription_name) do
    {Subscription, {stream_uuid, subscription_name}}
  end
end
