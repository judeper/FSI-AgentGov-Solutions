# Build Instructions — ValidateMimeTypePlugin

Step-by-step guide to build the Dataverse plugin DLL from source.

## Prerequisites

- Visual Studio 2019 or later
- .NET Framework 4.6.2 targeting pack

## Build Steps

1. **Create project:** Open Visual Studio → **Create a new project** → **Class Library (.NET Framework)** → Target framework: **.NET Framework 4.6.2** → Project name: `FsiAgentGovernance.Plugins`

2. **Strong-name signing:** Project Properties → **Signing** → check **Sign the assembly** → **New** (or browse for an existing `.snk` file). Dataverse sandbox-mode plugins require strong-name signing.

3. **Install NuGet packages:**
   ```
   Install-Package Microsoft.CrmSdk.CoreAssemblies -Version 9.0.2
   Install-Package System.Text.Json -Version 6.0.0
   Install-Package ILRepack -Version 2.0.18
   ```

4. **Add framework reference:** Right-click **References** → **Add Reference** → **Assemblies → Framework** → check **System.IO.Compression**. Required for `ZipArchive` usage in OpenXML validation.

5. **Set language version:** Open the `.csproj` file and add `<LangVersion>8.0</LangVersion>` inside the first `<PropertyGroup>`:
   ```xml
   <PropertyGroup>
     <!-- existing properties -->
     <LangVersion>8.0</LangVersion>
   </PropertyGroup>
   ```
   This enables `using var` syntax on .NET Framework 4.6.2.

6. **Configure ILRepack post-build event:** Add the following post-build event in Project Properties → **Build Events** → **Post-build event command line**:
   ```
   "$(SolutionDir)packages\ILRepack.2.0.18\tools\ILRepack.exe" /out:"$(TargetDir)FsiAgentGovernance.Plugins.dll" "$(TargetPath)" "$(TargetDir)System.Text.Json.dll" "$(TargetDir)System.Buffers.dll" "$(TargetDir)System.Memory.dll" "$(TargetDir)System.Numerics.Vectors.dll" "$(TargetDir)System.Runtime.CompilerServices.Unsafe.dll" "$(TargetDir)System.Text.Encodings.Web.dll" "$(TargetDir)System.Threading.Tasks.Extensions.dll" "$(TargetDir)System.ValueTuple.dll" /keyfile:"$(ProjectDir)YourKey.snk"
   ```
   > **Note:** Adjust the ILRepack version path and `.snk` filename to match your setup. The exact set of transitive dependency DLLs may vary by `System.Text.Json` version — include all DLLs that are copied to the output directory.

   Dataverse sandbox isolation only loads GAC-resident assemblies, so all NuGet dependencies must be merged into the plugin DLL.

7. **Add source file:** Copy `ValidateMimeTypePlugin.cs` into the project (or add it as an existing item).

8. **Build:** Build the solution (**Ctrl+Shift+B**). Output: `FsiAgentGovernance.Plugins.dll` in the `bin\Debug` or `bin\Release` folder.

## Verify

- The output DLL should be strong-name signed: `sn -vf FsiAgentGovernance.Plugins.dll`
- The DLL should contain merged dependencies (file size will be larger than the plugin code alone)

## Next Steps

Register the built DLL using the Plugin Registration Tool. See SOLUTION-DOCUMENTATION.md § Step 2: Register Dataverse Plugin for detailed registration instructions.
