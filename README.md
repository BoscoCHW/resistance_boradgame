# Avalon Web App Implementation

## Introduction
Our team of video game enthusiasts embarked on a journey to create an interactive game. Amidst brainstorming and polls, we settled on Avalon—a fun multiplayer party game that struck the right balance between complexity and feasibility within our timeline.

## Setup/Installation

### Prerequisites
- Elixir 1.18+
- Erlang 25+
- Postgres 15.2+ (with username as `postgres` and password as `postgres`)
- Phoenix Framework 1.7.2

### Installation Steps
1. Clone the repo. (Link in the bibliography below)
2. Run `mix setup` to install dependencies.
3. Launch the server with `mix phx.server` or `iex -S mix phx.server`.
4. Access the app via `localhost:4000`.

## Tools Used

### Frontend:
- **HTML**: Outlines the structure of pages.
- **CSS**: Specifies visual aspects of components, organized by the affected page.
- **JavaScript**: Connects client-side to server-side, configures connections, and initializes hooks and progress bars. Also used for TailWind CSS setup and importing "topbar" library.
- **Liveview**: Enables real-time updates without page refresh, handles game state updates, and bridges the game state and client updates.

### Backend:
- **Elixir**: Manages game logic and provides a multi-game capable server for real-time gameplay.

## Game Rules
1. Game starts with 5 players.
2. Players are divided as: 3 for the resistance and 2 as spies.
3. Only spies know each other's identities.
4. A leader is chosen randomly to begin the game.
5. Each round has a Team Building Phase and a Mission Phase.
6. Team Building involves discussions and the leader picking a mission team.
7. Missions teams vary in size by round: 2, 3, 2, 3, 3.
8. Players vote on the selected team. Approval sends them to the mission.
9. On missions, spies may sabotage. One sabotage fails the mission.
10. The game ends when one side wins three rounds.

## Development Process
From idea inception to detailed wireframes in Figma, our process was systematic. We divided our team into frontend and backend, used Trello for organization, and split our GitHub repo accordingly. Adopting new technologies like LiveView and Phoenix's PubSub, our class's combined knowledge from 3 months aided this project. Despite the time constraints of two weeks, we ensured an inclusive development process for everyone.


