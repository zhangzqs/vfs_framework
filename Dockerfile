# 构建时镜像
FROM dart:3.8.2 AS build

# 安装依赖
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

# 开始编译
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/vfs_framework.dart -o bin/vfs_framework

# 运行时镜像
FROM alpine:3.22.1
COPY --from=build /app/bin/vfs_framework /app/bin/
EXPOSE 8080
CMD ["/app/bin/vfs_framework"]
