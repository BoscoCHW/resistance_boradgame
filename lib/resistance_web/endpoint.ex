defmodule ResistanceWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :resistance

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_resistance_key",
    signing_salt: "Q3VmM+KL",
    same_site: "Lax"
  ]

  socket "/socket", ResistanceWeb.UserSocket, websocket: true, longpoll: false
  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :resistance,
    gzip: false,
    only: ResistanceWeb.static_paths()

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :resistance
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  # CORS configuration for separate React dashboard deployment
  plug CORSPlug,
    origin: [
      ~r/^https?:\/\/localhost:\d+$/,  # Development (any port)
      ~r/^https:\/\/.*\.vercel\.app$/,  # Vercel deployments
      ~r/^https:\/\/.*\.netlify\.app$/  # Netlify deployments
      # Add your production dashboard domain here
    ],
    methods: ["GET", "OPTIONS"],
    headers: ["Content-Type", "Authorization"]

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug ResistanceWeb.Router
end
