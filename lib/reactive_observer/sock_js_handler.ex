defmodule ReactiveObserver.SockJsHandler do
  require Logger

  defmodule State do
    defstruct session_id: :false, api: :false
  end

  def handle(_conn, :init, state) do
    #Logger.debug("SockJS init in state #{inspect state} PID=#{inspect self()}")
    {:new_connection, api} = state
    api.load_api()
    {:ok, %State{ api: api }}
  end
  def handle(conn, {:recv, data}, state) do
    #Logger.debug("SockJS data #{data} in state #{inspect state}")
    message=:jsx.decode(data,[labels: :existing_atom])
    {megasecs,secs,microsecs} =  :os.timestamp()
    ts = megasecs*1_000_000_000+secs*1_000+div(microsecs,1_000)
    tmessage=Map.put(message,:server_recv_ts,ts)
    case message(tmessage,conn,state) do
      {:reply, reply, rState} ->
        encoded = :jsx.encode(reply)
     #   Logger.debug("SockJS reply #{encoded} in state #{inspect rState}")
        :sockjs.send(encoded, conn)
        {:ok, rState}
      {:ok, rState} ->
        {:ok, rState}
    end
  end
  def handle(conn, {:info, info}, state) do
   # Logger.debug("SockJS info #{inspect info} in state #{inspect state}")
    case info(info,conn,state) do
      {:reply, reply, rState} ->
        encoded = :jsx.encode(reply)
   #     Logger.debug("SockJS send #{encoded} in state #{inspect rState}")
        :sockjs.send(encoded, conn)
        {:ok, rState}
      {:ok, rState} ->
        {:ok, rState}
    end
  end
  def handle(_conn, :closed, state) do
   # Logger.debug("SockJS close in state #{inspect state}")
    {:ok, state}
  end

  def message(%{type: "ping"}, req, state) do
    {:reply, %{type: "pong"}, state}
  end
  def message(%{type: "timeSync", server_recv_ts: recv_ts, client_send_ts: send_ts }, req, state) do
    {:reply, %{type: "timeSync", server_recv_ts: recv_ts, client_send_ts: send_ts, server_send_ts: recv_ts }, state}
  end
  def message(%{type: "initializeSession", sessionId: session_id},req,state=%State{ session_id: false}) do
    cond do
      byte_size(session_id)>100 -> {:error, "too long sessionId"}
      byte_size(session_id)<10 -> {:error, "too short sessionId"}
      true -> {:ok, %State{state | session_id: session_id}}
    end
    ## TODO: check for too much sessions/connections from one IP!
  end
  def message(_,_req,_state=%State{ session_id: false}) do
    {:error, :not_authenticated}
  end
  def message(%{ type: "request", to: to, method: method, args: args, requestId: request_id }, req, state) do
    reply=state.api.request(to,method,args,contexts(req,state))
    {:reply, %{type: "response", response: reply, responseId: request_id} , state}
  end
  def message(%{ type: "event", to: to, method: method, args: args }, req, state) do
    state.api.event(to,method,args,contexts(req,state))
    {:ok, state}
  end
  def message(%{ type: "observe", to: to, what: what }, req, state) do
    state.api.observe(to,what,contexts(req,state))
    {:ok, state}
  end
  def message(%{ type: "unobserve", to: to, what: what }, req, state) do
    state.api.unobserve(to,what,contexts(req,state))
    {:ok, state}
  end
  def message(%{ type: "get", to: to, what: what, requestId: request_id }, req, state) do
    reply=state.api.get(to,what,contexts(req,state))
    {:reply, %{type: "response", response: reply, responseId: request_id} , state}
  end
  def message(msg,_req,_state) do
    :io.format("unknown ws message ~p ~n",[msg])
    throw "unknown ws message"
  end

  def contexts(_req,state) do
    %{
      session_id: state.session_id,
      socket: self()
    }
  end

  def info(n={:notify,_,_,_},req,state) do
    {:notify,from,what,{signal,args}}=state.api.map_notification(n)
    data=%{
      type: "notify",
      from: from,
      what: what,
      signal: signal,
      args: args
    }
    {:reply, data, state}
  end
  def info(message, req, state) when is_map(message) do
  #  :io.format("sending message to client ~p ~n", [message])
    {:reply, message, state}
  end
  def info(info, _req, state) do
   # :io.format("unknown info received ~p in state ~p ~n", [info, state])
    {:error, :unknown_info}
  end
end