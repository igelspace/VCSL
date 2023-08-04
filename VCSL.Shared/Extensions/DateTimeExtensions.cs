using Microsoft.Graph;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace VCSL.Shared.Extensions;

/// <summary>
/// Class <c>DateTimeExtensions</c> extends the DateTime object.
/// </summary>
public static class DateTimeExtensions
{
    /// <summary>
    /// Method <c>ToLocalizedString</c> returns the localized version of ToString().
    /// </summary>
    public static string ToLocalizedString(this DateTime self, string format = "")
    {
        var date = self.ToLocalTime();
        return date.ToString(format);
    }
        
    /// <summary>
    /// Method <c>ToIsoDateString</c> converts a DateTime to an ISO compliant string.
    /// </summary>
    public static string ToIsoDateString(this DateTime self)
    {
        return $"{self.Year:D4}-{self.Month:D2}-{self.Day:D2}";
    }

    /// <summary>
    /// Method <c>ToIsoDateString</c> converts a nullable DateTime to an ISO compliant string.
    /// </summary>
    public static string? ToIsoDateString(this DateTime? self)
    {
        if (self == null)
            return null;
        return $"{self.Value.Year:D4}-{self.Value.Month:D2}-{self.Value.Day:D2}";
    }
}