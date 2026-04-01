# otel-instrumentation — Repo Context

Customer-facing OpenTelemetry instrumentation reference guide for Dynatrace.
Public repo under `gabriel-dynatrace`. Push only when explicitly instructed.

---

## What This Repo Is

A standalone developer reference — not internal docs, not tied to `dynatrace-cse`.
Audience: customers instrumenting applications with OTel and sending to Dynatrace.
Format follows the `smartscapes` developer guide: single-file guides, mermaid diagrams,
tables, real working examples, tips section, quick reference card.

---

## Files

| File | Purpose |
|------|---------|
| `README.md` | Main guide: SDK setup, auto/manual instrumentation, resource attributes, Collector pattern |
| `filelog-collector.md` | Dedicated guide: ingesting logs from files via OTel Collector filelog receiver |

---

## Validation Rules

**This is a customer-facing document. Do not reason about examples — verify everything.**

Before writing or modifying any example, fetch the relevant source doc. If it cannot
be fetched, flag it explicitly rather than inferring.

### Authoritative sources by topic

| Topic | Source |
|-------|--------|
| Dynatrace OTLP endpoints, token scopes | `https://docs.dynatrace.com/docs/ingest-from/opentelemetry/otlp-api` |
| filelog receiver params | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/receiver/filelogreceiver/README.md` |
| file_storage extension | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/extension/storage/filestorage/README.md` |
| Operators (move, add, etc.) | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/pkg/stanza/docs/operators/README.md` |
| Severity mapping syntax | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/pkg/stanza/docs/types/severity.md` |
| Timestamp layout directives | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/pkg/stanza/docs/types/timestamp.md` |
| Field path syntax | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/pkg/stanza/docs/types/field.md` |
| OTel resource semantic conventions | `https://opentelemetry.io/docs/specs/semconv/resource/` |
| Java zero-code agent | `https://opentelemetry.io/docs/zero-code/java/agent/` |
| Python zero-code | `https://opentelemetry.io/docs/zero-code/python/` |
| Node.js zero-code | `https://opentelemetry.io/docs/zero-code/js/` |
| OTLP exporter env vars | `https://opentelemetry.io/docs/concepts/sdk-configuration/otlp-exporter/` |
| resourcedetection processor | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/processor/resourcedetectionprocessor/README.md` |
| resource processor | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector-contrib/main/processor/resourceprocessor/README.md` |
| batch processor | `https://raw.githubusercontent.com/open-telemetry/opentelemetry-collector/main/processor/batchprocessor/README.md` |

---

## Confirmed Technical Facts

Decisions and facts verified against official docs during the creation of this guide.
Do not change these without re-validating against the source.

### Dynatrace OTLP

- **Protocol**: HTTP only. gRPC is NOT supported. Always set `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`.
- **SaaS endpoint**: `https://{environment-id}.live.dynatrace.com/api/v2/otlp`
- **Managed endpoint**: `https://{activegate-domain}:9999/e/{environment-id}/api/v2/otlp`
- **Containerized ActiveGate** (no port): `https://{activegate-domain}/e/{environment-id}/api/v2/otlp`
- **Token scope for traces**: `openTelemetryTrace.ingest`
- **Token scope for metrics**: `metrics.ingest`
- **Token scope for logs**: `logs.ingest`
- **Attribute limits**: key 1–100 chars, value 1–255 chars, max 50 dimensions per metric data point
- **Unsupported attribute types**: Double, Bytes, Array, Map — dropped on ingest. String, Boolean, Integer only.

### OTel Semantic Conventions

- **Deployment environment attribute**: `deployment.environment.name` (NOT `deployment.environment` — deprecated)
- **`OTEL_SERVICE_NAME`** takes precedence over `service.name` in `OTEL_RESOURCE_ATTRIBUTES`
- K8s attributes: `k8s.cluster.name`, `k8s.namespace.name`, `k8s.pod.name`, `k8s.container.name` — all confirmed

### Collector Exporter Naming

- Always use `otlphttp/dynatrace` (named instance), not the generic `otlphttp`.
  Matches Dynatrace documentation conventions and supports multi-exporter configs.

### filelog Receiver

- Config key is `filelog` (not `file_log`)
- `start_at` values: `beginning` or `end` (default: `end`)
- `on_truncate` values: `ignore` (default), `read_whole_file`, `read_new`
- `storage` references the `file_storage` extension by name
- `multiline` requires exactly one of `line_start_pattern` or `line_end_pattern`

### file_storage Extension

- Config key: `file_storage`
- `directory`: path to writable storage dir (default: `/var/lib/otelcol/file_storage`)
- `timeout`: default `1s`
- Must be declared in both `extensions:` block and `service.extensions:` list

### Stanza Operators

- `move` operator: `from` and `to` use field path syntax (`attributes.message`, `body`, `resource.uuid`)
- `body` by itself is a valid field destination (e.g. `to: body`)
- Severity mapping uses lowercase aliases (`error`, `warn`, `info`, `debug`, `fatal`)
- Severity mapping supports: single value, list, range (`min:`/`max:`), and HTTP patterns (`5xx`, `4xx`, `2xx`)
- `json_parser` and `regex_parser` both support embedded `timestamp:` and `severity:` blocks

### Timestamp Directives (strptime layout_type)

Confirmed valid directives from `timestamp.md`:

| Directive | Meaning |
|-----------|---------|
| `%Y` | 4-digit year |
| `%m` | 2-digit month |
| `%b` | Abbreviated month name (`Nov`) |
| `%d` | 2-digit day |
| `%H` | Hour (24h) |
| `%M` | Minute |
| `%S` | Second |
| `%L` | Millisecond, zero-padded (`123`) |
| `%f` | Microsecond, zero-padded |
| `%z` | Timezone offset `±HHMM` (e.g. `+0000`) — not `±HH:MM` |
| `%Z` | Timezone name or abbreviation (`UTC`) |

> **`%z` produces `±HHMM` format** (e.g. `+0000`), not `±HH:MM` (that is `%j`).

### Node.js Auto-Instrumentation

Zero-code approach (per official docs):
```bash
npm install --save @opentelemetry/api
npm install --save @opentelemetry/auto-instrumentations-node
export NODE_OPTIONS="--require @opentelemetry/auto-instrumentations-node/register"
node app.js
```

### Python

- `opentelemetry-bootstrap -a install` — confirmed valid flag syntax
- `LoggingInstrumentor().instrument(set_logging_format=True)` — confirmed valid parameter
- `opentelemetry-instrument --service_name your-service` — confirmed valid CLI argument

---

## Things That Were Wrong and Got Fixed

Track these so they don't regress.

| What was wrong | What it should be | Source |
|---------------|-------------------|--------|
| `deployment.environment` | `deployment.environment.name` | OTel semconv |
| `otlphttp:` exporter | `otlphttp/dynatrace:` | Dynatrace docs convention |
| `file_storage timeout: 10s` | `timeout: 1s` | filestorage README |
| `%L` removed from Java layout | `%L` is valid — restore it | timestamp.md |
| Nginx severity `range: min/max` | Use `5xx`/`4xx`/`2xx` patterns | severity.md |
| Nginx `add` operator with `EXPR()` | Removed — not in official docs | field.md / operators README |
| `%z` comment showing `+00:00` | `%z` produces `+0000` (no colon) | timestamp.md |
| Node.js: custom NodeSDK file | Use `--require` zero-code approach | OTel zero-code JS docs |
| `ResourceAttributes.DEPLOYMENT_ENVIRONMENT` | Deprecated; use env var | OTel semconv |
