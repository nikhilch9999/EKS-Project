FROM eclipse-temurin:17-jdk AS builder
WORKDIR /app
COPY src/Hello.java ./
RUN javac Hello.java

FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=builder /app/Hello.class ./
CMD ["java", "Hello"]
