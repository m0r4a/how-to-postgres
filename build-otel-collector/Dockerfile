# Compile
FROM golang:1.27.0-alpine AS builder
WORKDIR /build

ARG BUILDER_VERSION=0.159.0

RUN go install go.opentelemetry.io/collector/cmd/builder@v${BUILDER_VERSION}
COPY builder-config.yaml .
RUN sed -i "s/\${BUILDER_VERSION}/${BUILDER_VERSION}/g" builder-config.yaml \
	&& builder --config=builder-config.yaml

# Runtime
FROM alpine:3.24.1
RUN apk --no-cache add ca-certificates=20260611-r0
WORKDIR /otel
COPY --from=builder /build/otelcol-custom .
COPY otel-config.yaml .

EXPOSE 8889
CMD ["./otelcol-custom", "--config", "otel-config.yaml"]
