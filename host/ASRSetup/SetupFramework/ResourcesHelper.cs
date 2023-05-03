﻿namespace ASRSetupFramework
{
    using System;
    using System.Globalization;
    using System.Reflection;
    using System.Runtime.CompilerServices;
    using System.Windows;

    /// <summary>
    /// Static helper class to load resource dictionaries.
    /// </summary>
    public static class ResourcesHelper
    {
        /// <summary>
        /// Loads a resource dictionary that is inside this assembly.
        /// </summary>
        /// <param name="relativePath">resource dictionary path relative to the root of the project.</param>
        /// <returns>ResourceDictionary if loaded successfully.</returns>
        [MethodImpl(MethodImplOptions.NoInlining)]
        public static ResourceDictionary LoadInternal(string relativePath)
        {
            Assembly assembly = Assembly.GetCallingAssembly();
            return LoadExternal(assembly, relativePath);
        }

        /// <summary>
        /// Loads a resource dictionary that is outside this assembly.
        /// </summary>
        /// <param name="assembly">Assembly that contains the resource dictionary to be loaded.</param>
        /// <param name="relativePath">resource dictionary path relative to the root of the project.</param>
        /// <returns>ResourceDictionary if loaded successfully.</returns>
        public static ResourceDictionary LoadExternal(Assembly assembly, string relativePath)
        {
            ResourceDictionary dictionary = new ResourceDictionary();
            dictionary.Source = new Uri(string.Format(CultureInfo.InvariantCulture, @"pack://application:,,,/{0};component/{1}", assembly.FullName, relativePath));

            return dictionary;
        }
    }
}
