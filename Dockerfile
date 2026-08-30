# syntax=docker/dockerfile:1

# ---------- Stage 1: build the React frontend ----------
FROM node:20-alpine AS frontend-build
WORKDIR /app/frontend
COPY frontend/package.json ./
RUN npm install
COPY frontend/ ./
RUN npm run build
# Output lands in /app/frontend/dist

# ---------- Stage 2: build the Erlang release ----------
FROM erlang:26-alpine AS backend-build
RUN apk add --no-cache git build-base
WORKDIR /app

# Install rebar3
RUN wget -O /usr/local/bin/rebar3 https://s3.amazonaws.com/rebar3/rebar3 \
    && chmod +x /usr/local/bin/rebar3

COPY rebar.config ./
COPY src ./src
COPY include ./include
COPY config ./config

# Bake the built frontend into priv/static so cowboy_static can serve it.
COPY --from=frontend-build /app/frontend/dist ./priv/static

RUN rebar3 as prod release

# ---------- Stage 3: slim runtime image ----------
FROM erlang:26-alpine AS runtime
RUN apk add --no-cache ncurses-libs libstdc++
WORKDIR /app
COPY --from=backend-build /app/_build/prod/rel/chama ./

ENV PORT=8080
EXPOSE 8080

# chama_app.erl reads $PORT at boot (falling back to config/sys.config's
# http_port if unset), so this works both locally and on hosts like
# Render that assign the port dynamically.
CMD ["bin/chama", "foreground"]
