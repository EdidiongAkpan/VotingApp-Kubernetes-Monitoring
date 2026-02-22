#buildtime
FROM maven:3.8.7-eclipse-temurin-17 AS build
LABEL owner="Edidiongakpan18@gmail.com" description="dockerfile for sprinboot voting app"
RUN groupadd --system spring \
 && useradd --system --gid spring spring
WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests
#Runtime
FROM eclipse-temurin:17-jre
RUN addgroup --system spring && adduser --system --ingroup spring spring
WORKDIR /app
COPY --from=build /app/target/MySpring_Boot_aa23v_VotingApp_Final-0.0.1-SNAPSHOT.jar /app/MySpring_Boot_aa23v_VotingApp_Final-0.0.1-SNAPSHOT.jar
RUN chown -R spring:spring /app
USER spring
VOLUME ["/app/logs/volume"]
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "MySpring_Boot_aa23v_VotingApp_Final-0.0.1-SNAPSHOT.jar"]
