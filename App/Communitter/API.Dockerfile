FROM openjdk:17.0.2-slim-bullseye AS builder
WORKDIR /app
COPY . .
RUN ./mvnw clean install -DskipTests


FROM openjdk:17.0.2-slim-bullseye
WORKDIR /app
COPY --from=builder /app/target/Communitter-0.0.1-SNAPSHOT.jar /app/app.jar
CMD ["java", "-jar", "/app/app.jar"]