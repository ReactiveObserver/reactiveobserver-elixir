defmodule ReactiveObserver do
  require Logger

  def sockjs_handler(path,api) do
    state=:sockjs_handler.init_state(<<"/sockjs">>, &ReactiveObserver.SockJsHandler.handle/3, {:new_connection, api}, [])
    {path<>"/[...]", :sockjs_cowboy_handler, state}
  end
end
