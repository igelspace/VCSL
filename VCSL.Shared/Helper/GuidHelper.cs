using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace VCSL.Shared.Helper;

/// <summary>
/// Class <c>GuidHelper</c> provides helper functions for working with GUIDs.
/// </summary>
public static class GuidHelper
{
    /// <summary>
    /// Method <c>IsValidGuid</c> checks if a provided string is a valid GUID.
    /// </summary>
    /// <param name="str">the string that should be checked.</param>
    public static bool IsValidGuid(string str)
    {
        return Guid.TryParse(str, out _);
    }
}