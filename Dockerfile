# 第一阶段：构建
# *** 修改点1: 使用 slim 镜像作为 builder 阶段 ***
FROM node:20-bookworm-slim as builder

# 设置构建参数 (保持不变)
ARG COMMIT_HASH
ARG APPEND_PRESET_LOCAL_PLUGINS
ARG BEFORE_PACK_NOCOBASE="ls -l"
ARG PLUGINS_DIRS
ENV PLUGINS_DIRS=${PLUGINS_DIRS}

# 安装必要的系统依赖 (保持不变或根据需要调整)
RUN apt-get update && apt-get install -y jq && rm -rf /var/lib/apt/lists/*

# 设置工作目录 (保持不变)
WORKDIR /app

# 复制整个仓库代码 (保持不变)
COPY . .

# 安装所有依赖并构建 (保持不变)
RUN yarn install && yarn build --no-dts

# 如果有自定义构建后操作 (保持不变)
WORKDIR /app
RUN $BEFORE_PACK_NOCOBASE

# *** 修改点2: 清理和优化 ***
# 1. 移除不需要的构建产物或缓存
RUN rm -rf packages/app/client/src/.umi 2>/dev/null || true \
    # 移除源码 (通常构建后不需要)
    && rm -rf packages/*/src \
    # 移除测试文件 (如果有的话)
    && find . -type d -name "__tests__" -exec rm -rf {} + 2>/dev/null || true \
    && find . -type d -name "__mocks__" -exec rm -rf {} + 2>/dev/null || true \
    # 可以添加更多清理不需要的文件/目录的命令

# 2. *** 关键修改: 安装生产依赖 ***
#    这是减小体积最重要的一步。
#    通常有两种方式，这里选择在构建阶段清理并重新安装生产依赖：
#    方式 a: 如果你的项目结构允许直接在 /app 下执行 yarn install --production
#    方式 b: 如果需要在特定子目录安装，则需调整路径

#    假设你的最终应用代码在 /app 下，并且 package.json 也在 /app 下：
#    先备份 yarn.lock (如果需要保留原始信息用于调试，可选)
#    RUN cp yarn.lock yarn.lock.full
#    删除 node_modules
RUN rm -rf node_modules
#    重新只安装生产依赖
#    *** 修改点3: 使用 --production 标志 ***
RUN yarn install --production --network-timeout 600000 -g
#    (可选) 清理 yarn 缓存
RUN yarn cache clean --force

# 3. *** 修改点4: 清理不必要的文件 (模仿官方) ***
#    删除 yarn.lock 文件本身（如果确定运行时不需要）
#    RUN rm -f yarn.lock
#    删除 node_modules 中的开发相关配置文件
RUN find node_modules -type f -name "yarn.lock" -delete \
    && find node_modules -type f -name "bower.json" -delete \
    && find node_modules -type f -name "composer.json" -delete \
    # 可以根据需要添加更多清理规则，例如 .md, .map, .ts 等非运行时必需文件 (需谨慎)
    # && find node_modules -type f \( -name "*.md" -o -name "*.map" \) -delete

# 4. 打包应用 (修改打包路径为当前目录，即清理和安装生产依赖后的 /app)
#    *** 修改点5: 确保打包的是优化后的目录 ***
RUN rm -rf /tmp/nocobase.tar.gz 2>/dev/null || true \
    # 注意：这里 -C /app 表示打包 /app 目录的内容
    && tar -zcf /tmp/nocobase.tar.gz -C /app . 

# 第二阶段：运行时镜像 (保持不变或微调)
FROM node:20-bookworm-slim

# 安装运行时依赖 (保持不变)
RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx \
    libaio1 \
    libfreetype6 \
    fontconfig \
    libgssapi-krb5-2 \
    fonts-liberation \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

# 配置 Nginx (保持不变)
RUN rm -rf /etc/nginx/sites-enabled/default
COPY ./docker/nocobase/nocobase.conf /etc/nginx/sites-enabled/nocobase.conf

# 从 builder 阶段复制打包文件 (保持不变)
COPY --from=builder /tmp/nocobase.tar.gz /app/nocobase.tar.gz

# 解压应用文件 (保持不变)
WORKDIR /app
RUN mkdir -p nocobase \
    && tar -zxf nocobase.tar.gz -C nocobase \
    && rm -f nocobase.tar.gz

# 创建必要的目录并记录 commit hash (保持不变)
WORKDIR /app/nocobase
RUN mkdir -p storage/uploads/ \
    && if [ -n "$COMMIT_HASH" ]; then echo "$COMMIT_HASH" >> storage/uploads/COMMIT_HASH; fi

# 复制入口脚本 (保持不变)
COPY ./docker/nocobase/docker-entrypoint.sh /app/

# 设置执行权限 (保持不变)
RUN chmod +x /app/docker-entrypoint.sh

# 启动命令 (保持不变)
CMD ["/app/docker-entrypoint.sh"]
