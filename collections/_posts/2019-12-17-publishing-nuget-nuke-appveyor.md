---
layout: post
title:  "Publishing .NET Core NuGet Packages with Nuke and AppVeyor"
author: camron
categories: [development]
image: assets/images/nuke-appveyor-build-image.png
tags: [featured, appveyor, nuke, dotnet, nuget]
---

This article builds on concepts discussed by [Andrew Lock](https://andrewlock.net/publishing-your-first-nuget-package-with-appveyor-and-myget/), [Jimmy Bogard](https://lostechies.com/jimmybogard/2016/05/24/my-oss-cicd-pipeline/) and [Georg Dangl](https://blog.dangl.me/archive/escalating-automation-the-nuclear-option/). Here we're going use [Nuke](https://nuke.build/) to make build, packaging and publishing even nicer!!! 

I've been eking out build solutions using various Powershell based tools for years.  They serve their purpose, but I always dread getting familiar with the scripts again when I need to make a change.  I recently used [Nuke](https://nuke.build/) on a project and for the first time I feel like I didn't waste any time fighting with it.  

Nuke creates a CSharp Console App within your solution containing a simple <code>Build.cs</code> file that can handle a variety of common build/deployment tasks out of the box.  The real joy is that you can now author and debug platform independent build scripts in C# within your favorite IDE!

Let's jump in. 

<h4>Using Nuke to Build</h4>

- Install Nuke
<pre>
> dotnet tool install Nuke.GlobalTool --global
</pre>

- Add Nuke to your solution - let the wizard get you started
<pre>
> nuke :setup
</pre>
<img src="/assets/images/nuke-setup-screen.png" alt="nuke setup" title="nuke setup" height="400"/>
<div class="alert alert-warning" role="alert">
  <strong>Warning:</strong> For me the Nuke build project defaulted to .NET Core 3.0.  This isn't necessarily a problem, but it's worth noting.  This was true when buidling an app on .NET Core 2.2; so it's a bit odd for my build environment to require .Net Core 3.0<br/>  
  TODO:/// Figure out Nuke's logic for framework selection and see if it's configurable     
</div>

You'll notice a new project in your solution named <code>_build</code>.  Take note of a few files
1. <code>Build.cs</code> - a fluent "make style" build Class in C#
    * Defines targets and their dependencies
2. Two scripts used to run builds.  These scripts will install dotnet if it doesn't exist and then call your build application.  Choose one based on your build environment. 
    * <code>build.ps1</code> - a powershell script used to execute builds (platform independent - must have powershell installed) 
    * <code>build.sh</code> - a shell script version (linux/osx/etc..)

- Now compile your code
<pre>
>  .\build.ps1 Compile
</pre>
<img src="/assets/images/nuke-compile-screen.png" alt="nuke compile" title="nuke compile" height="600"/>

**Success!** I'll admit that compiling a project isn't that impressive, but we're now scripting in C#.  Let's take it a step further and make a NuGet package.

- Add a __Pack__ step to our build script

```csharp
Target Pack => _ => _
      .DependsOn(Compile)
      .Executes(() =>
      {
          DotNetPack(s => s
              .SetProject(Solution.GetProject("Nuke.Sample"))
              .SetConfiguration(Configuration)
              .EnableNoBuild()
              .EnableNoRestore()
              .SetDescription("Sample package produced by NUKE")
              .SetPackageTags("nuke demonstration c# library")
              .SetNoDependencies(true)
              .SetOutputDirectory(ArtifactsDirectory / "nuget"));

      });
```

We want our NuGet package to specify an author, repository, homepage, etc...  We could do this programatically from Nuke

```csharp
 Target Pack => _ => _
      .DependsOn(Compile)
      .Executes(() =>
      {
          DotNetPack(s => s
               ***
              .SetAuthors("Your Name")
              .SetPackageProjectUrl("https://github.com/yourrepo/NukeSample")
               ***
      });
```

- But it's simpler to add a <code>Directory.Build.props</code> to your solution folder

```xml
 <Project>
  <PropertyGroup>
    <Authors>Your Name</Authors>
    <RepositoryUrl>https://github.com/yourrepo/NukeSample</RepositoryUrl>
    <PackageProjectUrl>https://github.com/yourrepo/NukeSample</PackageProjectUrl>
    <PackageLicense>https://github.com/yourrepo/NukeSample/blob/master/LICENSE</PackageLicense>
  </PropertyGroup>
</Project>
```

- Now call our new __Pack__ target
<pre>
>  .\build.ps1 Pack
</pre>

Now we've got our nuget package: <code>artifacts\nuget\Nuke.Sample.1.0.0.nupkg</code>.  If we unzip the .nupkg file we can take a look inside at our <code>Nuke.Sample.nuspec</code> file. 

```xml
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2012/06/nuspec.xsd">
  <metadata>
    <id>Nuke.Sample</id>
    <version>1.0.0</version>
    <authors>Your Name</authors>
    <owners>Your Name</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance>
    <projectUrl>https://github.com/yourrepo/NukeSample</projectUrl>
    <description>Sample package produced by NUKE</description>
    <tags>nuke demonstration c# library</tags>
    <repository url="https://github.com/yourrepo/NukeSample" />
    <dependencies>
      <group targetFramework=".NETStandard2.0" />
    </dependencies>
  </metadata>
</package>
```

<strong>Success!</strong>  Not bad for a few minutes of our time.  Before we move on let's touch on versioning.  If you have an approach that you love, it shouldn't be hard to work it into our current workflow with Nuke.  Here we'll consider a manual option and using the popular [GitVersion](https://gitversion.readthedocs.io/en/latest/) tool.

<h6>Manual Versioning</h6>
 - Let's add add a couple of lines to our <code>Directory.Build.props</code>.

```xml
 <Project>
  <PropertyGroup>
    ---
    <VersionPrefix>0.1.1</VersionPrefix>
    <VersionSuffix>alpha</VersionSuffix>
  </PropertyGroup>
</Project>
```

- Now let's call our __Pack__ target again
<pre>
>  .\build.ps1 Pack
</pre>

Our package name reflects the new version: <code>artifacts\nuget\Nuke.Sample.0.1.1-alpha.nupkg</code>.  If we unzip and look inside <code>Nuke.Sample.nuspec</code> we can see the updated version.

```xml
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2012/06/nuspec.xsd">
  <metadata>
    <id>Nuke.Sample</id>
    <version>0.1.1-alpha</version>
```
<h6>Versioning with GitVersion tool</h6>
Nuke has great integration with the [GitVersion](https://gitversion.readthedocs.io/en/latest/) tool. You'll need to read the [docs](https://gitversion.readthedocs.io/en/latest/) to fully understand how GitVersion determines the current version name for a branch, but to use - simply:

- Add these 2 properties to your <code>Build.cs</code> class
```csharp
    [GitRepository] readonly GitRepository GitRepository;
    [GitVersion] readonly GitVersion GitVersion;
```
- Add the <code>.SetVersion(GitVersion.NuGetVersionV2)</code> to your __Pack__ Target
```csharp
 DotNetPack(s => s
             ---
            .SetVersion(GitVersion.NuGetVersionV2)
            .SetNoDependencies(true)
            .SetOutputDirectory(ArtifactsDirectory / "nuget"));
```            
Now GitVersion will work it's magic to determine the current version name!

<h5>Publishing to a NuGet Repository with Nuke</h5>

Now that we have our source compiling and our package versioned and waiting in our artifacts folder, lets use Nuke to push it to a repository where it can be used by others.   

In order to make this as flexible as possible, we'll pass the nuget repository's url and auth_key as parameters to the Nuke build script.  Inside the script Nuke makes it easy for us to 
* Require that it's a Release build
* Require that the url and auth_key have been set
* Get values from commandline / environment using c# fields

- Add 2 Fields to to your Build file with the [Parameter] attribute 

```csharp
    [Parameter] string NugetApiUrl = "https://api.nuget.org/v3/index.json"; //default
    [Parameter] string NugetApiKey;
```
- Add a __Push__ Target to your Build file

```csharp
 Target Push => _ => _
       .DependsOn(Pack)
       .Requires(() => NugetApiUrl)
       .Requires(() => NugetApiKey)
       .Requires(() => Configuration.Equals(Configuration.Release))
       .Executes(() =>
       {
           GlobFiles(NugetDirectory, "*.nupkg")
               .NotEmpty()
               .Where(x => !x.EndsWith("symbols.nupkg"))
               .ForEach(x =>
               {
                   DotNetNuGetPush(s => s
                       .SetTargetPath(x)
                       .SetSource(NugetApiUrl)
                       .SetApiKey(NugetApiKey)
                   );
               });
       });
```
- __Push__ to a NuGet repository
<pre>
> ./build.ps1 Push --NugetApiUrl "https://api.nuget.org/v3/index.json" --NugetApiKey "yoursecretkey"   
</pre>

<h4>Using AppVeyor for Continuous Integration and Deployment</h4>

[AppVeyor](https://www.appveyor.com/) is a CI/CD tool with good support for windows/dotnet (and linux).  For open source projects you can setup a free account to build and deploy every time you publish changes to source control.  Here we're going to use [GitHub](https://www.github.com), but you could configure something similar with [Azure DevOps](https://azure.microsoft.com/en-us/services/devops/)

We're going to build a popular workflow as described by [Andrew Lock](https://andrewlock.net/publishing-your-first-nuget-package-with-appveyor-and-myget/) and [Jimmy Bogard](https://lostechies.com/jimmybogard/2016/05/24/my-oss-cicd-pipeline/).  It uses two seperate nuget repositories to publish under different conditions:

- Build all commits on <code>master</code> branch and publish to [MyGet.org](https://www.myget.org/)
  * Useful for reviewing and testing packages before releasing to the world
  * Nightly/experimental builds
- If a commit is tagged we want to build and publish to [NuGet.org](https://www.nuget.org/)
  * Allows us to use git tags to control versioning and our intent to publish to the world
- Build-only for pull request 
  * We don't want to publish a nuget package on pull requests, but we will confirm that the pull request builds 


We can accomplish all of this with a simple appveyor.yml file.  

- Add <code>appveyor.yml</code> to our root folder

```
version: '{build}'
image: Ubuntu
environment:
MyGetApiKey:
    secure: 56nW3KcP4naYX9mlsVEIKLj5xPdfmpt6lMALR6wQmorRQOaoUOtlwMZ2V0BtGTAM
NugetApiKey:
    secure: /54XAunyBETRa1Fp/qSrwvebSnTAcHDO2OVZ+exMtQtOtrBzHKvp4RC1AB8RD2PQ
pull_requests:
do_not_increment_build_number: true
branches:
only:
- master
nuget:
disable_publish_on_pr: true
build_script:
- ps: ./build.ps1
test: off
deploy_script:
- ps: ./build.ps1 Pack
- ps: ./build.ps1 Push --NugetApiUrl "https://www.myget.org/F/cfrenzel-ci/api/v2/package" --NugetApiKey $env:MyGetApiKey
- ps: | 
    if ($env:APPVEYOR_REPO_TAG  -eq "true"){
        ./build.ps1 Push --NugetApiUrl "https://api.nuget.org/v3/index.json" --NugetApiKey $env:NugetApiKey
    }
```

There are a couple of important bits here
<pre>
build_script:
    - ps: ./build.ps1
</pre>
This tells appveyor to call our Nuke build script during the build phase
<pre>
 deploy_script:
    - ps: ./build.ps1 Pack
    - ps: ./build.ps1 Push --NugetApiUrl "https://www.myget.org/F/cfrenzel-ci/api/v2/package" --NugetApiKey $env:MyGetApiKey
    - ps: | 
        if ($env:APPVEYOR_REPO_TAG  -eq "true"){
            ./build.ps1 Push --NugetApiUrl "https://api.nuget.org/v3/index.json" --NugetApiKey $env:NugetApiKey
        }
</pre>
This tells appveyor to run a series of powershell commands during the Deploy phase. 
* We call __Pack__ to create the nuget package.  
* Then we __Push__ it to MyGet.org using secure environment variables that we declared earlier
* Then we check an appveyor environement variable <code>APPVEYOR_REPO_TAG</code> to see if the branch has a tag
* If it does we __Push__ to NuGet.Org

For a full working example with multiple nuget packages in a single solution checkout out my repo:

[https://github.com/cfrenzel/Eventfully/blob/master/build/Build.cs](https://github.com/cfrenzel/Eventfully/blob/master/build/Build.cs)
[https://github.com/cfrenzel/Eventfully/blob/master/appveyor.yml](https://github.com/cfrenzel/Eventfully/blob/master/appveyor.yml)
[https://github.com/cfrenzel/Eventfully](https://github.com/cfrenzel/Eventfully)

