using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using OpenTelemetry;
using OpenTelemetry.Exporter;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

// Register a low-level ActivityListener at the very top of Program.cs, BEFORE any
// host or DI is built. This ensures Source.StartActivity() returns a real Activity
// from the very first invocation. On Azure Functions Linux .NET 8 isolated workers,
// the OTel SDK's internal listener has been observed to silently disappear after
// process suspensions — the listener registration is process-wide state that the
// runtime can clear. A standalone, statically-held listener side-steps that.
ActivitySourceBootstrap.RegisterListener();

var builder = FunctionsApplication.CreateBuilder(args);
builder.ConfigureFunctionsWebApplication();

var serviceName = Environment.GetEnvironmentVariable("OTEL_SERVICE_NAME") ?? "gabriel-otel-demo";
var otlpBase = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT")
    ?? throw new InvalidOperationException("OTEL_EXPORTER_OTLP_ENDPOINT must be set");
var otlpHeaders = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_HEADERS") ?? string.Empty;

// Pin the TracerProvider to a STATIC field so the GC cannot reclaim it. On the
// Azure Functions .NET 8 isolated worker, holding the TracerProvider only via DI
// (singleton or otherwise) was observed to silently lose its internal ActivityListener
// after the first cold-start invocation — spans then stop being exported even though
// ForceFlush returns true. A static reference keeps the listener alive for the whole
// process lifetime. (See README "Gotchas" for the diagnostic story.)
TracerProviderHolder.Instance = Sdk.CreateTracerProviderBuilder()
    .ConfigureResource(r => r.AddService(serviceName))
    .AddSource("GabrielOtelDemo.HelloHttp")
    .AddSource("GabrielOtelDemo.Heartbeat")
    .AddHttpClientInstrumentation()
    // SimpleProcessor exports synchronously per Activity.Stop. Avoids batch races on
    // suspended workers. For higher-volume apps, switch to BatchActivityExportProcessor
    // + explicit ForceFlush at end of each function invocation.
    .AddProcessor(new SimpleActivityExportProcessor(new OtlpTraceExporter(new OtlpExporterOptions
    {
        Endpoint = new Uri(otlpBase.TrimEnd('/') + "/v1/traces"),
        Protocol = OtlpExportProtocol.HttpProtobuf,
        Headers = otlpHeaders,
    })))
    .Build()!;

builder.Services.AddSingleton(TracerProviderHolder.Instance);
builder.Services.AddHttpClient();

builder.Build().Run();

public static class TracerProviderHolder
{
    public static TracerProvider Instance = null!;
}

// Always-on ActivityListener that says "yes, sample this" for our sources. The
// TracerProvider's processors (including the OTLP exporter) still process spans
// — this just guarantees Activity creation isn't dropped if the OTel-internal
// listener gets cleared by a worker-process lifecycle event.
public static class ActivitySourceBootstrap
{
    private static System.Diagnostics.ActivityListener? _listener;
    public static void RegisterListener()
    {
        if (_listener != null) return;
        _listener = new System.Diagnostics.ActivityListener
        {
            ShouldListenTo = src => src.Name.StartsWith("GabrielOtelDemo"),
            Sample = (ref System.Diagnostics.ActivityCreationOptions<System.Diagnostics.ActivityContext> _) =>
                System.Diagnostics.ActivitySamplingResult.AllDataAndRecorded,
            SampleUsingParentId = (ref System.Diagnostics.ActivityCreationOptions<string> _) =>
                System.Diagnostics.ActivitySamplingResult.AllDataAndRecorded,
        };
        System.Diagnostics.ActivitySource.AddActivityListener(_listener);
    }
}
