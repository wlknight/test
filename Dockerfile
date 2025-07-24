FROM node:20-bookworm AS builder
ARG VERDACCIO_URL=http://host.docker.internal:10104/
ARG COMMIT_HASH
ARG APPEND_PRESET_LOCAL_PLUGINS
ARG BEFORE_PACK_NOCOBASE="ls -l"




WORKDIR /tmp
COPY . /tmp
RUN  yarn install && yarn build --no-dts

#SHELL ["/bin/bash", "-c"]



#RUN git config user.email "test@mail.com"  \
    #&& git config user.name "test" && git add .  \
    #&& git commit -m "chore(versions): test publish packages"
#RUN yarn release:force --registry $VERDACCIO_URL

#RUN yarn config set registry $VERDACCIO_URL

WORKDIR /tmp
RUN $BEFORE_PACK_NOCOBASE

RUN rm -rf packages/app/client/src/.umi \
  && mkdir -p /app \
  && tar --exclude=node_modules -zcf /app/nocobase.tar.gz -C /tmp .


FROM node:20-bookworm

RUN corepack enable

#RUN apt-get update && apt-get install -y --no-install-recommends wget gnupg ca-certificates \
  #&& rm -rf /var/lib/apt/lists/*

#RUN echo "deb [signed-by=/usr/share/keyrings/pgdg.asc] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list
#RUN wget --quiet -O /usr/share/keyrings/pgdg.asc https://www.postgresql.org/media/keys/ACCC4CF8.asc

RUN apt-get update && apt-get install -y --no-install-recommends \
  nginx \
  libaio1 \
  #postgresql-client-16 \
  #postgresql-client-17 \
  libfreetype6 \
  fontconfig \
  libgssapi-krb5-2 \
  fonts-liberation \
  fonts-noto-cjk \
  build-essential \
  python3 \
  && rm -rf /var/lib/apt/lists/*

RUN rm -rf /etc/nginx/sites-enabled/default
COPY ./docker/nocobase/nocobase.conf /etc/nginx/sites-enabled/nocobase.conf
WORKDIR /app

COPY --from=builder /app/nocobase.tar.gz /app/nocobase.tar.gz

RUN mkdir -p /app/nocobase \
  && tar -zxf nocobase.tar.gz -C /app/nocobase \
  && rm -f nocobase.tar.gz

WORKDIR /app/nocobase

RUN yarn install --production --ignore-optional

# RUN apt-get purge -y --auto-remove build-essential python3 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/nocobase/storage/uploads/ && echo "$COMMIT_HASH" >> /app/nocobase/storage/uploads/COMMIT_HASH

COPY ./docker/nocobase/docker-entrypoint.sh /app/

CMD ["/app/docker-entrypoint.sh"]
