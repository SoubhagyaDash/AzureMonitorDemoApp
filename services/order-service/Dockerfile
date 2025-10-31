# Use the official OpenJDK image as a parent image
FROM eclipse-temurin:17-jdk-alpine as build

WORKDIR /app

# Copy the Maven wrapper and pom.xml
COPY pom.xml ./
COPY src ./src

# Install Maven
RUN apk add --no-cache maven

# Build the application
RUN mvn clean package -DskipTests

# Use a smaller JRE image for the final image
FROM eclipse-temurin:17-jre-alpine

WORKDIR /app

# Copy the built JAR file from the build stage
COPY --from=build /app/target/*.jar app.jar

# Expose the port the app runs on
EXPOSE 8080

# Set environment variables
ENV SPRING_PROFILES_ACTIVE=docker

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]