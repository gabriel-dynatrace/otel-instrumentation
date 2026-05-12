using System.Diagnostics;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace GabrielOtelDemo;

public class HelloHttp(ILogger<HelloHttp> logger)
{
    private static readonly ActivitySource Source = new("GabrielOtelDemo.HelloHttp");

    [Function("HelloHttp")]
    public IActionResult Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", "post")] HttpRequest req)
    {
        using var span = Source.StartActivity("hello.http", ActivityKind.Server);
        span?.SetTag("http.route", "/api/HelloHttp");

        logger.LogInformation("HelloHttp invoked, traceId={T}", span?.TraceId);

        return new OkObjectResult(new
        {
            message = "Welcome to Azure Functions! (OTel→Dynatrace demo)",
            traceId = span?.TraceId.ToString(),
            spanId = span?.SpanId.ToString(),
        });
    }
}
