FROM --platform=$BUILDPLATFORM maven:3-eclipse-temurin-21 AS build
WORKDIR /app
COPY ./pom.xml .
COPY ./src ./src
RUN mvn package -DskipTests

FROM eclipse-temurin:21-jre-alpine
RUN apk upgrade --no-cache
RUN addgroup -S app && adduser -S -G app app
WORKDIR /app
COPY --from=build /app/target/openapi-workshop-1.0.0.jar app.jar
RUN mkdir /data && chown app:app /data
USER app:app
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
CMD ["--server.port=8080"]