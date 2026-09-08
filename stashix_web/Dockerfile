FROM elixir:1.18-alpine AS build

WORKDIR /app

RUN apk add --no-cache build-base git nodejs npm vips-dev

COPY mix.exs mix.lock ./
RUN mix local.hex --force && mix local.rebar --force
RUN MIX_ENV=prod mix deps.get --only prod

COPY config config
RUN MIX_ENV=prod mix deps.compile

COPY assets assets
COPY priv priv
COPY lib lib

RUN MIX_ENV=prod mix assets.deploy
RUN MIX_ENV=prod mix release

FROM alpine:3.24

RUN apk add --no-cache libstdc++ openssl ncurses-libs p7zip unrar vips

WORKDIR /app

COPY --from=build /app/_build/prod/rel/stashix ./

ENV PHX_HOST=localhost PORT=4000 MIX_ENV=prod

EXPOSE 4000

CMD ["./bin/stashix", "start"]
