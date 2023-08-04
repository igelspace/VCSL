using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using VCSL.Shared.Models;

namespace VCSL.Download.DependencyInjection;

internal static class DependencyInjectionSetup
{
    public static IServiceCollection AddAppConfiguration(this IServiceCollection services, IConfiguration config)
    {
        services.Configure<VcslOptions>(config.GetSection("Values"));
        return services;
    }
}