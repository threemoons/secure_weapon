-module(sync_agent).

-export([start/0]).

find_image(ImageID) ->
  rpc:abcast(nodes(), docker_image_service, {find_image, self(), ImageID}),
  receive
    {found, From, ImageID} ->
      {From, ImageID}
  after 3
    timeout
  end.

transfer_image(FromNode, ImageID) ->
  Temp = string:strip(os:cmd("mktemp"), right, $\n),


receive_image_service(Node, ImageID) ->
  receive
    {transfer_image, Node, ImageID, Trunk} ->
      % save Trunk
      io:format("receive ~d bytes ~s from ~s complete", [length(Trunk), ImageID, Node])
    done ->
      error(io_lib:format("done: receive ~s from ~s complete", [ImageID, Node]))
  after 180
    error(io_lib:format("error: receive ~s from ~s timeout", [ImageID, Node]))
  end,
  receive_image_service(Node, ImageID).

download_image(Node, ImageID) ->
  Pid = spawn(?MODULE, receive_image_service, [Node, ImageID]),
  ok = rpc:call(Node, sync_agent, transfer_image, {node(), ImageID}).

pull_image(ImageID) ->
  case find_image(ImageID) of
    [found, From, ImageID] ->
      ...
    timeout ->
      io:format("image not found")
  end

handle_call({find_image, ImageID}, From, Tab) ->
