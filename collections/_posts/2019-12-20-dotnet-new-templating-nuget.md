---
layout: post
title:  "Quickly Create Your Own .NET Code Templates And Use Them From Anywhere"
author: camron
categories: [development]
image: assets/images/dotnet-new.png
tags: [featured, dotnet, automation, nuget, appveyor]
---

Whether you need to throw together a quick console app or scaffold an enterprise solution, it can be a real time suck just creating, naming and referencing projects.  Setting up boilerplate logging, dependency injection, data access, messaging, gulp and other tools can send you hunting through previous work to copy and paste code.  Let's put an end to all that once and for all with less than an hour of work using <code>dotnet new</code> templating! The advantages of this approach include:

    - Use a tool that's already on any development machine       
    - No new templating language to learn
    - Use runnable Solution/Project/Files as templates
    - Bundle many templates into a single distributable package
    - Access templates from any machine with a single command

<h4>Let's get started:</h4>

Our goal is to be able to easily create and distribute custom templates to any machine; so let's first take a look at what templates already exist on our machine:

```console
> dotnet new -l
```
<pre>
Templates                                         Short Name               Language          Tags
----------------------------------------------------------------------------------------------------------------------------------
Console Application                               console                  [C#], F#, VB      Common/Console
Class library                                     classlib                 [C#], F#, VB      Common/Library
</pre>

You should see a list of templates longer but similar to above.  Our custom templates will show up in this list when we're done.  To create a new project from the template named <code>console</code> in the list above we can type:

```console
>  dotnet new console -n SampleFromTemplate
```
This will create a new folder with a console app named <code>SampleFromTemplate</code>.  It's ready to go with nuget packages restored and the namespaces set to *SampleFromTemplate*.
<pre>
SampleFromTemplate
    └─── SampleFromTemplate.csproj
    └─── Program.cs
    └─── /obj
</pre>

To begin creating custom templates with <code>dotnet new</code> simply create a normal project or solution (or just one or more files) that represents your boilerplate code for a given scenario.  That's almost all there is to it.  Adding a configuration file to setup some metadata and behavior will result in a resuable template.  The template folder structure for a simple console app project will look something like this:

<pre>
└───mycustomtemplate
    └─── Templating.ConsoleApp.csproj
    └─── Program.cs
    └─── /.template_config
        └───  template.json
</pre>

* Start with any existing project and from the project root folder

```console
>  mkdir .template_config
```
<div class="alert alert-warning">
 You have control over whether the generated output of your template is placed in a new folder or just dumped in the output location.  If you want everything inside a folder then include the folder at the top level of the template beside the <code>.template_config</code> folder.  Otherwise you can leave it up to the user to specify on the command line using the <code>-o</code> option.  
</div>
<div class="alert alert-warning">
If you want to create empty folders inside your template such as <code>/src</code> <code>/test</code> <code>/doc</code> <code>/build</code> <code>/migrations</code>.  For now you will need to place a file named <code>-.-</code> inside the folder otherwise the empty folder will be ignored in the output
</div>


- Add a <code>template.json</code> to the <code>.template_config</code> folder

```javascript
{
  "$schema": "http://json.schemastore.org/template",
  "author": "Camron Frenzel",
  "classifications": [ "cfrenzel", "core", "console" ],
  "tags": {
    "language": "C#"
  },
  "identity": "demo.console",
  "name": "demo.console_2.2",
  "shortName": "dm-console-2.2",
  "sourceName": "Templating",
  "sources": [
    {
      "modifiers": [
        { "exclude": [ ".vs/**", ".template_config/**" ] }
      ]
    }
  ],
}
```

- <code>identity</code> a unique name for the template 
- <code>name</code> for display purposes
- <code>shortName</code> what users will type to specify your template
- <code>sources -> exclude:</code> This is a little trick to keep some unwanted files out of the template 
- <code>sourceName</code> the name in the source tree to replace with the user specified name (using <code>-n</code> or <code>--name</code>). 

    **<code>sourceName</code> is important!**.  <code>dotnet new</code> will replace all the folders/files/namespaces/etc.. containing this name with whatever the user passes in on the command line.  For example: If I'm using a convention such as
    <pre>
    └─── Templating.sln
    └─── /src
        └─── /Templating.ConsoleApp
            └─── Templating.ConsoleApp.csproj
        └─── /Templating.Domain
            └─── Templating.Domain.csproj
        └─── /Templating.Application
            └─── Templating.Application.csproj
    </pre>

    Then passing in <code>-n Demo</code>  will produce:
    ```console
    >  dotnet new demo.console_2.2 -n Demo
    ```
    <pre>
    └─── Demo.sln
    └─── /src
        └─── /Demo.ConsoleApp
            └─── Demo.ConsoleApp.csproj
        └─── /Demo.Domain
            └─── Demo.Domain.csproj
        └─── /Demo.Application
            └─── Demo.Application.csproj
    
     namespaces: Templating.ConsoleApp -> Demo.ConsoleApp
  </pre>

- At this point you should be comfortable with these concepts
    - a template is a normal solution/project/file
    - add a <code>.template_config</code> folder with a <code>template.config</code> file in it to configure a template
     - the user will pass in a --name *MyApp* to the template that will replace the configured <code>sourceName</code> text in all folders/solutions/projects/namespaces


<div class="alert alert-primary">
<strong>Tip!</strong> To have nuget restore automatically - add this to your template.config
<pre>
"symbols": {
    "skipRestore": {
      "type": "parameter",
      "datatype": "bool",
      "description": "If specified, skips the automatic restore of the project on create.",
      "defaultValue": "false"
    }
  },
  "postActions": [
    {
      "condition": "(!skipRestore)",
      "description": "Restore NuGet packages required by this project.",
      "manualInstructions": [
        { "text": "Run 'dotnet restore'" }
      ],
      "actionId": "210D431B-A78B-4D2F-B762-4ED3E3EA9025",
      "continueOnError": true
    }
  ]
  </pre>
</div>

<div class="alert alert-danger">
<strong>Issue!</strong>  If your template creates one or more projects, often you would like the generated projects to be automatically added to an existing solution.  This is supported, but I haven't had any luck with it.  The essence of the problem seems to be a bug rendering the output project path/name.  

<pre>
  "primaryOutputs": [
    { "path": "SolutionName.ConsoleApp/SolutionName.ConsoleApp.csproj" }
  ],

  "postActions": [
    {
      "description": "Add project to solution",
      "manualInstructions": [],
      "primaryOutputIndexes": "0",
      "actionId": "D396686C-DE0E-4DE6-906D-291CD29FC5DE",
      "continueOnError": true
    }
  ]
</pre> 
  <a href="https://github.com/dotnet/templating/issues/1489">https://github.com/dotnet/templating/issues/1489</a>
</div>


If you haven't created your own template at this point you can follow along by downloading a console app template with logging/DI/configuration [here](https://github.com/cfrenzel/dotnet-new-templates-2.2/tree/master/templates/ConsoleApp)

<h4>Installing a template</h4>

We could install our template locally from the template root folder.

```console
dotnet new -i .
```

List the installed templates and you should see your template listed
```console
dotnet new -l
```

You can use it by passing in it's <code>shortName</code> and provide a name
```console
    >  dotnet new {shortname} -n DemoApp
```

To remove your template 
```console
dotnet new -u
```
You should see your template along with an <code>Uninstall command:</code>.  This command will come in handy as things can get confusing when managing multiple versions of your templates and installing them from different sources. 

```console
 dotnet new -u C:\temptemplate\temptemplate
```

Not bad, but the workflow leaves a lot to be desired.  It would be a pain to manage even a modest number of templates using this method.

<h4>Packaging templates</h4>

The <code>dotnet new</code> templating tool supports installing templates from nuget packages locally or in remote repositories.  Multiple templates can be included in a single package, which allows adding and removing collections of templates from the internet with a single command.

Packaging templates took some tinkering for me; so let's get straight to what works by creating a special project that will help us get all of our templates into a single package.  The structure of our multi-template solution will look like this:

<pre>
 └─── /my-dotnet-templates   
      └─── my-dotnet-templates.sln
      └─── /templates
           └─── Directory.Build.props //metadata for package
           └─── templates.csproj
           └─── /ConsoleApp //template 1
                └─── Templating.sln
                └─── /.template_config
                     └───template.json
                └─── /Templating.ConsoleApp
                     └─── Templating.ConsoleApp.csproj
           └─── /WebApp //template 2
                └─── Templating.sln
                └─── /.template_config
                     └───template.json
                └─── /Templating.WebbApp
                     └─── Templating.WebApp.csproj
           
</pre>

The idea is that you have a solution with a /templates folder and a special project: <code>template.csproj</code> that will aid in building the multi-template package. Within the 
/templates folder you will have a folder for each template.  The folder for each template should contain everything you need to develop and test the template. You won't be able to run the template from our special <code>templates.csproj</code> so it's nice to have a seperate solution for running/editing each template.

- You can start by creating <code>templates.csproj</code> as a console app.  Open the .csproj file and edit it to look like this:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <PackageType>Template</PackageType>
    <TargetFramework>netcoreapp2.2</TargetFramework>
    <PackageId>cfrenzel-dotnet-new-templates-2.2</PackageId>
    <Title>cfrenzel dotnet-new-templates</Title>
    <IncludeContentInPack>true</IncludeContentInPack>
    <IncludeBuildOutput>false</IncludeBuildOutput>
    <ContentTargetFolders>content</ContentTargetFolders>
  </PropertyGroup>

  <ItemGroup>
    <Content Include="ConsoleApp\**" Exclude="ConsoleApp\SolutionName.sln;ConsoleApp\**\bin\**;ConsoleApp\**\obj\**;ConsoleApp\**\.vs\**" />
    <Content Include="EFCore.MigrationProjects\**" Exclude="EFCore.MigrationProjects\**\bin\**;EFCore.MigrationProjects\**\obj\**;EFCore.MigrationProjects\**\.vs\**" />
    <Content Include="Solution\**" Exclude="Solution\**\bin\**;Solution\**\obj\**;Solution\**\.vs\**" />
    <Compile Remove="**\*" />
  </ItemGroup>

</Project>
```
   - ```<PackageType>Template</PackageType>``` - set special package type for project
   - For each template in our package we are adding a ```<Content>``` tag that specifies which files to include and exclude
     - ```<Content Include="ConsoleApp\**"``` - include everything from our /ConsoleApp folder
     - ```Exclude="ConsoleApp\Templating.sln;ConsoleApp\**\bin\**;ConsoleApp\**\obj\**;ConsoleApp\**\.vs\**" />``` - exclude the solution file and bin/obj folders
   - ```<Compile Remove="**\*" />``` - we're not interested in the output of the compiled project

- We can specify metadata for the package in <code>Directory.Build.props</code> 

```xml
<Project>
  <PropertyGroup>
    <Authors>Camron Frenzel</Authors>
    <RepositoryUrl>https://github.com/cfrenzel/dotnet-new-templates-2.2.git</RepositoryUrl>
    <PackageProjectUrl>https://github.com/cfrenzel/dotnet-new-templates-2.2</PackageProjectUrl>
    <Description>dotnet new templates for core 2.2</Description>
    <PackageTags>template dotnet console migration web</PackageTags>
    <PackageLicense></PackageLicense>
    <Version>1.0.0</Version>   
  </PropertyGroup>
</Project>
```

- Now we can create our nuget package using <code>templates.csproj</code>

```console
dotnet pack .\templates\templates.csproj -o .\artifacts\ --no-build
```

And install all of our templates locally from our <code>.nupkg</code> file

```console
dotnet new -i .\artifacts\cfrenzel-dotnet-new-templates-2.2.1.0.0
```

Find the <code>Uninstall command:</code> to remove
```console
dotnet new -u
```

<h4>Publish package for access online</h4>

You can host your template .nupkg for free using my [MyGet](https://www.myget.org/) or make it official/perminent using [NuGet.org](https://www.nuget.org/).  This can be as simple as typing

```console
dotnet nuget push artifacts\**\*.nupkg -s "https://www.myget.org/F/{youraccount}/api/v2/package" -k {yourkey}
```

Then installing your templates from anywhere using

```console
dotnet new --install {yourpackagename}  --nuget-source https://www.myget.org/F/{youraccount}/api/v3/index.json
```
<div class="alert alert-primary">
  If you publish it to <strong>nuget.org</strong> you don't even have to specify the package url!
  dotnet new --install {yourpackagename}
</div>

-Since we're pretty much one configuration file away from free continuous build and deployment, let's setup [AppVeyor](https://www.appveyor.com/) to build and publish our template package every time we commit a change to the source code.

- Save you code to [Github](https://github.com) or wherever
- Add an <code>appveyor.yml</code> to build and publish template package to MyGet

```
version: '1.{build}'
image: Visual Studio 2019
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
test: off
build_script:
  - dotnet restore 
  - dotnet pack .\templates\templates.csproj -o .\artifacts\ --no-build
deploy_script:
  - ps: dotnet nuget push artifacts\**\*.nupkg -s "https://www.myget.org/F/cfrenzel-ci/api/v2/package" -k $env:MyGetApiKey
 
```
After you link your AppVeyor project to your source repo, your template .nupkg will be updated in MyGet/Nuget every time you commit to master.


<h4>Final Thoughts</h4>
Though templating with <code>dotnet new</code> has some more powerful features including:
 - conditional logic
 - custom parameters
 - post actions
 - multi-language
 - [see docs - template.json](https://github.com/dotnet/templating/wiki/Reference-for-template.json)

I really appreciate the simplicity of the tool.  You simply use what you're already doing to make doing what you're already doing faster.  No need to learn a new complex template language.


[full source code ](https://github.com/cfrenzel/dotnet-new-templates-2.2) for this post.