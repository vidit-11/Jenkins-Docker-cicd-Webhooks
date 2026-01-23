# --- Stage 1: Build & Test ---
FROM maven:3.9.6-eclipse-temurin-17-alpine AS build
WORKDIR /app
# Copy pom.xml and download dependencies
COPY pom.xml .
RUN mvn dependency:go-offline

# Copy source code and build the JAR
COPY src ./src
RUN mvn clean package

# --- Stage 2: Tiny Runtime ---
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
# Copy only the compiled JAR from the build stage
COPY --from=build /app/target/*.jar app.jar
EXPOSE <port>
ENTRYPOINT ["java", "-jar", "app.jar"]
