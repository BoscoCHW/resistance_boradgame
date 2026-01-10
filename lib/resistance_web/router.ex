defmodule ResistanceWeb.Router do
  use ResistanceWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {ResistanceWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ResistanceWeb do
    pipe_through :api

    get "/analytics/stats", AnalyticsController, :stats
    get "/analytics/health", AnalyticsController, :health
    get "/rooms", RoomsController, :index
  end

  scope "/", ResistanceWeb do
    pipe_through :browser

    live "/lobby/:room_code", LobbyLive, :lobby
    live "/game/:room_code", GameLive, :game

    # catch-all route
    live "/*path", HomeLive, :home
  end

end
