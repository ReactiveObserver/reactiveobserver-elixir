defmodule ReactiveObserver do
  require Logger

  def sockjs_handler(path,api,opts) do
    state=:sockjs_handler.init_state(<<"/sockjs">>, &ReactiveObserver.SockJsHandler.handle/3, {:new_connection, api, opts}, [])
    {path<>"/[...]", :sockjs_cowboy_handler, state}
  end
end
