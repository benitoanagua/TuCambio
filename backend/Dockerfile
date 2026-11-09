FROM gradle:9.2.1-jdk21 AS build
WORKDIR /workspace

COPY settings.gradle.kts build.gradle.kts gradle.properties ./
COPY src ./src

RUN gradle --no-daemon clean installDist

FROM eclipse-temurin:21-jre-jammy AS runtime
WORKDIR /app

RUN groupadd --system --gid 10001 app     && useradd --system --uid 10001 --gid app app

COPY --from=build --chown=app:app /workspace/build/install/tucambio-backend /app

ENV PORT=8080
EXPOSE 8080

USER 10001:10001
ENTRYPOINT ["/app/bin/tucambio-backend"]
