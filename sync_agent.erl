-module(sync_agent).
-compile(export_all).

start() ->
  register(docker_image_service, spawn(?MODULE, lookfor_service, [])).

% ask cluster lookfor image
find_image(ImageID) ->
  rpc:abcast(nodes(), docker_image_service, {find_image, self(), ImageID}),
  receive
    {found, From, ImageID} ->
      {found, From, ImageID}
  after 2000 ->
    io:format("wait timeout...."),
    timeout
  end.

lookfor_service() ->
  receive
    {find_image, Pid, ImageID} ->
      DockerInspect = string:strip(os:cmd("docker inspect " ++ ImageID ++ " && echo 1"), right, $\n),
      Result = lists:last(DockerInspect),
      % io:format("Result is ~s", [1]),
      if
        Result =:= $1 ->
          Pid ! {found, node(), ImageID};
        true ->
          io:format("not found image: ~s on ~s", [ImageID, node()])
      end
  end.
  %lookfor_service().

% send image
transfer_image(FromNode, ImageID) ->
  Temp = string:strip(os:cmd("mktemp"), right, $\n),
  DockerSave = string:strip(os:cmd("docker save -o " ++ Temp ++ " " ++ ImageID ++ " && echo 1"), right, $\n),
  Result = lists:last(DockerSave),
  if
    Result =:= $1 ->
      {ok, IoDevice} = file:open(Temp, read),
      transfer_image_in_trunk(FromNode, ImageID, IoDevice),
      ok = file:close(IoDevice);
    true ->
      io:format("save image: ~s at ~s failed", [ImageID, node()])
  end.

transfer_image_in_trunk(FromNode, ImageID, IoDevice) ->
  case file:read(IoDevice, 4096) of
    {ok, Data} ->
      transfer_image_in_trunk(FromNode, ImageID, IoDevice),
      rpc:abcast([FromNode], receive_image_service, {transfer_image, node(), ImageID, Data});
    eof ->
      rpc:abcast([FromNode], receive_image_service, {done, node(), ImageID});
    {error, Reason} ->
      io:format("transfer image error: ~s", [Reason]),
      rpc:abcast([FromNode], receive_image_service, {error, node(), ImageID, Reason})
  end.


% receive image from node
receive_image_service(Node, ImageID, IoDevice) ->
  io:format("start receive ~p from ~p", [ImageID, Node]),
  receive
    {transfer_image, Node, ImageID, Trunk} ->
      % save Trunk
      file:write(IoDevice, Trunk),
      io:format("receive ~p bytes ~s from ~s complete", [length(Trunk), ImageID, Node]),
      receive_image_service(Node, ImageID, IoDevice);
    {done, Node, ImageID} ->
      io:format("done: receive ~s from ~s complete", [ImageID, Node]),
      file:close(IoDevice);
    {error, Node, ImageID, Reason} ->
      error(io_lib:format("error: receive ~s from ~s failed, ~s", [ImageID, Node, Reason]))
  end.

% download image from node
download_image(Node, ImageID, FilePath) ->
  {ok, IoDevice} = file:open(FilePath, write),
  register(receive_image_service, spawn(?MODULE, receive_image_service, [Node, ImageID, IoDevice])),
  ok = rpc:call(Node, sync_agent, transfer_image, [node(), ImageID]).

pull_image(ImageID) ->
  case find_image(ImageID) of
      {found, From, ImageID} ->
        Temp = string:strip(os:cmd("mktemp"), right, $\n),
        download_image(From, ImageID, Temp),
        DockerLoad = os:cmd("docker load -i " ++ Temp),
        io:format("Docker ~s", [DockerLoad]);
    timeout ->
      io:format("image not found ~n"),
      notfound
  end.
