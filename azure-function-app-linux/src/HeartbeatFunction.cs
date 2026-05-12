using System.Diagnostics;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace GabrielOtelDemo;

// Self-generates traces on a schedule so customers see data flowing without any
// manual HTTP invocation. Two timer-triggered functions, distinct patterns:
//   Tick     — parent span + outbound HTTP dependency + occasional exception
//   Pipeline — three nested child spans (fetch → transform → publish)
public class HeartbeatFunction(ILogger<HeartbeatFunction> logger, IHttpClientFactory httpFactory)
{
    private static readonly ActivitySource Source = new("GabrielOtelDemo.Heartbeat");
    private static long _tickCount;

    [Function("Tick")]
    public async Task Tick([TimerTrigger("*/30 * * * * *")] TimerInfo timer)
    {
        var n = Interlocked.Increment(ref _tickCount);

        using var parent = Source.StartActivity("heartbeat.tick", ActivityKind.Internal);
        parent?.SetTag("iteration", n);

        // Outbound HTTP call — HttpClient instrumentation auto-creates a child client span,
        // demonstrating a dependency span in the trace view.
        using (var child = Source.StartActivity("outbound.http", ActivityKind.Internal))
        {
            try
            {
                var http = httpFactory.CreateClient();
                http.Timeout = TimeSpan.FromSeconds(5);
                var resp = await http.GetAsync("https://httpbin.org/uuid");
                child?.SetTag("http.response.status_code", (int)resp.StatusCode);
            }
            catch (Exception ex)
            {
                child?.SetStatus(ActivityStatusCode.Error, ex.Message);
                child?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
                {
                    { "exception.type", ex.GetType().FullName! },
                    { "exception.message", ex.Message },
                    { "exception.stacktrace", ex.ToString() },
                }));
                logger.LogWarning(ex, "outbound http call failed (non-fatal)");
            }
        }

        // Every 10th tick, raise + record an exception to exercise error-span capture.
        if (n % 10 == 0)
        {
            try
            {
                throw new InvalidOperationException(
                    $"synthetic failure on tick #{n} — demonstrates error span capture");
            }
            catch (Exception ex)
            {
                parent?.SetStatus(ActivityStatusCode.Error, ex.Message);
                parent?.AddEvent(new ActivityEvent("exception", tags: new ActivityTagsCollection
                {
                    { "exception.type", ex.GetType().FullName! },
                    { "exception.message", ex.Message },
                    { "exception.stacktrace", ex.ToString() },
                }));
                logger.LogError(ex, "synthetic exception captured on tick {N}", n);
            }
        }

        logger.LogInformation("Tick #{N} complete", n);
    }

    [Function("Pipeline")]
    public async Task Pipeline([TimerTrigger("0 */1 * * * *")] TimerInfo timer)
    {
        using var run = Source.StartActivity("pipeline.run", ActivityKind.Internal);

        using (var fetch = Source.StartActivity("pipeline.fetch", ActivityKind.Internal))
        {
            await Task.Delay(Random.Shared.Next(50, 150));
            fetch?.SetTag("rows", Random.Shared.Next(100, 1000));
        }

        using (var transform = Source.StartActivity("pipeline.transform", ActivityKind.Internal))
        {
            await Task.Delay(Random.Shared.Next(100, 300));
            transform?.SetTag("rules.applied", Random.Shared.Next(3, 12));
        }

        using (var publish = Source.StartActivity("pipeline.publish", ActivityKind.Internal))
        {
            await Task.Delay(Random.Shared.Next(30, 80));
            publish?.SetTag("destination", "demo-sink");
        }

        logger.LogInformation("Pipeline run complete");
    }
}
