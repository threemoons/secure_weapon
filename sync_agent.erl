-module(sync_agent).
-compile(export_all).

start() ->
  register(docker_image_service, spawn(?MODULE, lookfor_service, [])).

% ask cluster lookfor image
find_image(ImageID) ->
  rpc:abcast(nodes(), docker_image_service, {find_image, self(), ImageID}),
  receive
    {found, From, ImageID} ->
      {From, ImageID}
  after 2000 ->
    timeout
  end.

lookfor_service() ->
  receive
    {find_image, Pid, ImageID} ->
      DockerInspect = string:strip(os:cmd("docker inspect " ++ ImageID ++ " && echo 1"), right, $\n),
      Result = lists:last(DockerInspect),
      if
        Result =:= $1 ->
          Pid ! {found, node(), ImageID};
        true ->
          io:format("not found image: ~s on ~s", [ImageID, node()])
      end
  end.

% send image
transfer_image(FromNode, ImageID) ->
  Temp = string:strip(os:cmd("mktemp"), right, $\n),
  DockerSave = string:strip(os:cmd("docker save -o " ++ Temp ++ " " ++ ImageID ++ " && echo 1"), right, $\n),
  Result = lists:last(DockerSave),
  if
    Result =:= $1 ->
      {ok, IoDevice} = file:open(Temp, read),
      transfer_image_in_trunk(FromNode, ImageID, IoDevice),
      ok = file:close(Temp);
    true ->
      io:format("save image: ~s at ~s failed", [ImageID, node()])
  end.

transfer_image_in_trunk(FromNode, ImageID, IoDevice) ->
  case file:read(IoDevice, 4096) of
    {ok, Data} ->
      rpc:cast(FromNode, sync_agent, receive_image_service, {transfer_image, node(), ImageID, Data});
    eof ->
      rpc:cast(FromNode, sync_agent, receive_image_service, {done, node(), ImageID});
    {error, Reason} ->
      io:format("transfer image error: ~s", [Reason]),
      rpc:cast(FromNode, sync_agent, receive_image_service, {error, node(), ImageID, Reason})
  end.


% receive image from node
receive_image_service(Node, ImageID) ->
  receive
    {transfer_image, Node, ImageID, Trunk} ->
      % save Trunk
      io:format("receive ~s bytes ~s from ~s complete", [length(Trunk), ImageID, Node]),
      receive_image_service(Node, ImageID);
    {done, Node, ImageID} ->
      io:format("done: receive ~s from ~s complete", [ImageID, Node]);
    {error, Node, ImageID, Reason} ->
      error(io_lib:format("error: receive ~s from ~s failed, ~s", [ImageID, Node, Reason]))
  after 180000 ->
    error(io_lib:format("error: receive ~s from ~s timeout", [ImageID, Node]))
  end.

% download image from node
download_image(Node, ImageID) ->
  Pid = spawn(?MODULE, receive_image_service, [Node, ImageID]),
  ok = rpc:call(Node, sync_agent, transfer_image, {node(), ImageID}).

pull_image(ImageID) ->
  case find_image(ImageID) of
    [found, From, ImageID] ->
      download_image(From, ImageID);
    timeout ->
      io:format("image not found ~n"),
      notfound
  end.
