# 第一阶段：构建
FROM node:20-bookworm as builder

# 设置构建参数
ARG COMMIT_HASH
ARG APPEND_PRESET_LOCAL_PLUGINS
ARG BEFORE_PACK_NOCOBASE="ls -l"
ARG PLUGINS_DIRS

ENV PLUGINS_DIRS=${PLUGINS_DIRS}

# 安装必要的系统依赖
RUN apt-get update && apt-get install -y jq

# 设置工作目录
WORKDIR /app

# 复制整个仓库代码
COPY . .

# 安装依赖并构建
RUN yarn install && yarn build --no-dts

# 如果有自定义构建后操作
WORKDIR /app
RUN $BEFORE_PACK_NOCOBASE

# 打包应用（假设构建后的文件在当前目录）
RUN rm -rf packages/app/client/src/.umi 2>/dev/null || true \
  && rm -rf /tmp/nocobase.tar.gz 2>/dev/null || true \
  && tar -zcf /tmp/nocobase.tar.gz -C /app .

# 第二阶段：运行时镜像
FROM node:20-bookworm-slim

# 安装运行时依赖
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
  && rm -rf /var/lib/apt/lists/*

# 配置 Nginx
RUN rm -rf /etc/nginx/sites-enabled/default
COPY ./docker/nocobase/nocobase.conf /etc/nginx/sites-enabled/nocobase.conf

# 从 builder 阶段复制打包文件
COPY --from=builder /tmp/nocobase.tar.gz /app/nocobase.tar.gz

# 解压应用文件
WORKDIR /app
RUN mkdir -p nocobase \
  && tar -zxf nocobase.tar.gz -C nocobase \
  && rm -f nocobase.tar.gz

# 创建必要的目录并记录 commit hash
WORKDIR /app/nocobase
RUN mkdir -p storage/uploads/ \
  && if [ -n "$COMMIT_HASH" ]; then echo "$COMMIT_HASH" >> storage/uploads/COMMIT_HASH; fi

# 复制入口脚本
COPY ./docker/nocobase/docker-entrypoint.sh /app/

# 设置执行权限
RUN chmod +x /app/docker-entrypoint.sh

# 启动命令
CMD ["/app/docker-entrypoint.sh"]