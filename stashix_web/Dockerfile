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

RUN apk add --no-cache libstdc++ openssl ncurses-libs p7zip vips \
    && printf '#!/bin/sh\ncase "$1" in\n  lb) 7z l -ba "$2" | awk '"'"'{print $NF}'"'"' ;;\n  p) archive="$3"; file="$4"; 7z x -so "$archive" "$file" ;;\n  *) echo "unsupported: $1" >&2; exit 1 ;;\nesac\n' > /usr/local/bin/unrar \
    && chmod +x /usr/local/bin/unrar

WORKDIR /app

COPY --from=build /app/_build/prod/rel/stashix ./
COPY entrypoint.sh ./entrypoint.sh
RUN chmod +x ./entrypoint.sh

ENV PHX_HOST=localhost PORT=4000 MIX_ENV=prod

EXPOSE 4000

CMD ["./entrypoint.sh"]
