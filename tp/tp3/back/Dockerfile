FROM ubuntu:24.04

RUN apt-get update
RUN apt-get install -y openjdk-17-jdk-headless maven

WORKDIR /app
COPY . .
RUN mvn package -DskipTests

RUN mkdir -p /data
CMD ["java", "-jar", "target/openapi-workshop-1.0.0.jar"]