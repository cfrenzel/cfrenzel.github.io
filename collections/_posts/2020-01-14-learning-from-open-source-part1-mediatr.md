---
layout: post
title:  "Learning From Open Source Part1: MediatR"
author: camron
categories: [development]
image: assets/images/mediatr.jpeg
tags: [featured, mediatR, tutorial]
---

It can be intimidating and time consuming to explore a mature open source project.  Often an attempt to find inspiration just results in a surface level understanding of a few components with no real insight into the **magic**.  In this series I hope to find projects of just the right size and complexity to "get in there" and learn something.  Let's take a look a [MediatR](https://github.com/jbogard/MediatR).

I use MediatR in many projects because of its "simple to use" yet powerful implementation of the [Mediator Pattern](https://en.wikipedia.org/wiki/Mediator_pattern).  Essentially the mediator sits between method callers and receivers creating a configurable layer of abstraction that determines how callers and receivers get wired up.  

Let's look at a quick example of a Controller calling some Application Layer code with MediatR.  


```csharp
public class CreateTicketCommand : IRequest<CreateTicketResponse>
{
    public string Description { get; set; }
    public string Department { get; set; }
    public string Severity { get; set; }
}

public class TicketController: Controller
{
   private readonly IMediator _mediator;

    public TicketController(IMediator mediator)
    {
        _mediator = mediator;
    }

    [HttpPost]
    public async Task<ActionResult> Create(CreateTicketModel model)
    {
        var command = new CreateTicketCommand()
        {
            Description = model.Description,
            Department = model.Department,
            Severity = model.Severity
        };

        var res = await _mediator.Send(command);
        return RedirectToAction("Show", new { id = res.TicketId});
    }
}
```

There are a few things to notice here.  
- The Command defines the type of it's response `IRequest<CreateTicketResponse>`
- The `IMediator` is injected into the Controller
- There is a single `Send` method on the `IMediator` used to dispatch all command/message types   
- The Controller doesn't know who is receiving/handling the command

Here's a sample handler for <code>CreateTicketCommand</code>

```csharp
public class CreateTicketHandler : IRequestHandler<CreateTicketCommand, CreateTicketResponse>
{
    private readonly ApplicationDbContext _db;

    public CreateTicketHandler(ApplicationDbContext db) =>  _db = db;

    public async Task<CreateTicketResponse> Handle(CreateTicketCommand command, CancellationToken cancellationToken)
    {
        Ticket ticket = new Ticket(command.Description, command.Department, command.Severity);
        _db.Tickets.Add(ticket);
        await _db.SaveChangesAsync();
        return new CreateTicketResponse() { TicektId = ticket.Id };
    }
}
```

Notice:
- Handler doesn't know who sent the command
- Handler specifies the the message type that it handles and the response type `IRequestHandler<CreateTicketCommand, CreateTicketResponse>`
- Handler has constructor parameters that must be injected by the Mediator



We configure MediatR in our app's startup with a single line

```csharp
  services.AddMediatR(typeof(Program));
 ```

 Here's what I'm thinking
 - I never registered any handlers explicitly; so I know that MediatR is scanning my assembly for handlers.  This is pretty common and shouldn't be much different than something like ASP.NET MVC finding your controllers, but I'd like to look under the hood a little.

 - The call to `_mediator.Send(command)` stands out as the interesting bit.  Somehow this method can take any request type, find a concrete handler implementation for that request type, instantiate it, and call it.  Let's try to uncover the **magic** behind this!

**Going to the Source**

Let's dig in.  First download the source or browse online at [https://github.com/jbogard/MediatR/tree/master/src/MediatR](https://github.com/jbogard/MediatR/tree/master/src/MediatR)

<pre>
> git clone https://github.com/jbogard/MediatR.git .
</pre>

You'll first notice a handful of simple interfaces and `Mediator.cs` with the core class.  Since we're curious about it's `Send` method let's take a look inside.  The file is surprisingly small, and at first glance it looks like the `Send` method is actually doing some of the real work. 

```csharp
        public Mediator(ServiceFactory serviceFactory)
        {
            _serviceFactory = serviceFactory;
        }

        public Task<TResponse> Send<TResponse>(IRequest<TResponse> request, CancellationToken cancellationToken = default)
        {
            if (request == null)
            {
                throw new ArgumentNullException(nameof(request));
            }

            var requestType = request.GetType();

            var handler = (RequestHandlerWrapper<TResponse>)_requestHandlers.GetOrAdd(requestType,
                t => Activator.CreateInstance(typeof(RequestHandlerWrapperImpl<,>).MakeGenericType(requestType, typeof(TResponse))));

            return handler.Handle(request, cancellationToken, _serviceFactory);
        }
```

First things first, above I made a call using `Send(command)`, but the send method here is generic `Send<TResponse>(IRequest<TResponse> request)`.  It turns out that the compiler can infer the type argument; so you can omit it.  Our call above looks much prettier than `Send<CreateTicketResponse>(command)` [(generics methods).](https://docs.microsoft.com/en-us/dotnet/csharp/programming-guide/generics/generic-methods)  Moving on...

I'm starting to get excited because the `Send` method is basically a fat one-liner, yet it appears to be instantiating a handler and calling it (which is the primary purpose of the mediator).   Let's dig a little deeper.

```csharp
var handler = (RequestHandlerWrapper<TResponse>)_requestHandlers.GetOrAdd(requestType,
                t => Activator.CreateInstance(typeof(RequestHandlerWrapperImpl<,>).MakeGenericType(requestType, typeof(TResponse))));
```

The outer `_requestHandlers.GetOrAdd` is just checking if a handler already exists before creating a new one. The real magic seems to be:

```csharp
Activator.CreateInstance(typeof(RequestHandlerWrapperImpl<,>).MakeGenericType(requestType, typeof(TResponse)))
```

We're getting close to something.   We're taking a `RequestHandlerWrapperImpl<,>` calling `MakeGenericType(requestType, typeof(TResponse))` on it then instantiating the result which is apparently assignable to `RequestHandlerWrapper<TResponse>`.  Let's plug in our command type above to see if it makes more sense

```csharp
typeof(RequestHandlerWrapperImpl<,>).MakeGenericType(typeof(CreateTicketCommand), typeof(CreateTicketResponse))
```

This gives us a `RequestHandlerWrapperImpl<CreateTicketCommand,CreateTicketResponse>` which is assignable to `RequestHandlerWrapper<CreateTicketResponse>`.  For now let's think of "RequestHandlerWrapper" as some kind of wrapper around our actual handler (`CreateTicketHandler`).  We know that instantiating our actual handler will need our Dependency Injection container to resolve the dependencies (like ApplicationDbContext); so perhaps the wrapper is hiding these details.  But whats up with the cast from `RequestHandlerWrapperImpl` down to the less generic `RequestHandlerWrapper`?  Believe it or not, this seemingly benign cast is part of the real **magic**.  The bigger concept at play here is a technique for allowing non-generic code to call into generic code.  It's a little hard to see here because the return type is still generic, but notice how the `TRequest` goes away when casting `RequestHandlerWrapperImpl<TRequest,TResponse>` to `RequestHandlerWrapper<TResponse>`.

Lets take a look inside:

```csharp
 
 internal abstract class RequestHandlerWrapper<TResponse> : RequestHandlerBase
    {
        public abstract Task<TResponse> Handle(IRequest<TResponse> request, CancellationToken cancellationToken,
            ServiceFactory serviceFactory);
    }
 
 internal class RequestHandlerWrapperImpl<TRequest, TResponse> : RequestHandlerWrapper<TResponse>
        where TRequest : IRequest<TResponse>
    {
         public override Task<TResponse> Handle(IRequest<TResponse> request, CancellationToken cancellationToken,
            ServiceFactory serviceFactory)
        {
            Task<TResponse> Handler() => GetHandler<IRequestHandler<TRequest, TResponse>>(serviceFactory).Handle((TRequest) request, cancellationToken);

            return serviceFactory
                .GetInstances<IPipelineBehavior<TRequest, TResponse>>()
                .Reverse()
                .Aggregate((RequestHandlerDelegate<TResponse>) Handler, (next, pipeline) => () => pipeline.Handle((TRequest)request, cancellationToken, next))();
        }
```

Cool. So `RequestHandlerWrapperImpl<TRequest, TResponse>` inherits from the abstract `RequestHandlerWrapper<TResponse>`.  So we have the generic implementation extending the non-generic (with respect to TRequest).  Ultimately, `RequestHandlerWrapper<TResponse>` is providing a single non-generic handler interface that we can use to make calls into all the generic implementations for each request/message type.  Let's see how the generic version accomplishes this:      


```csharp
 public override Task<TResponse> Handle(IRequest<TResponse> request, CancellationToken cancellationToken,
            ServiceFactory serviceFactory)
        {
            Task<TResponse> Handler() => GetHandler<IRequestHandler<TRequest, TResponse>>(serviceFactory).Handle((TRequest) request, cancellationToken);

            return serviceFactory
                .GetInstances<IPipelineBehavior<TRequest, TResponse>>()
                .Reverse()
                .Aggregate((RequestHandlerDelegate<TResponse>) Handler, (next, pipeline) => () => pipeline.Handle((TRequest)request, cancellationToken, next))();
        }
```

MediatR has some cool features around pipelines, but a basic mediator doesn't need any of that.  Let's focus on how the `RequestHandlerWrapperImpl<TRequest, TResponse>` does it's job of calling our `CreateTicketHandler` with this line:

```csharp
Task<TResponse> Handler() => GetHandler<IRequestHandler<TRequest, TResponse>>(serviceFactory).Handle((TRequest) request, cancellationToken);

```

Let's break this down

- First we call `GetHandler()` on our base `RequestHandlerBase` class.  This should return our actual handler (`CreateTicketHandler`).  We'll take a look inside a little later

```csharp
GetHandler<IRequestHandler<TRequest, TResponse>>(serviceFactory)
```

- Then we call the `Handle()` method on the actual handler (`CreateTicketHandler`).  We must cast the `IRequest<TResponse>` to `TRequest` to complete the bridge from the non-generic to generic.    

```csharp
.Handle((TRequest) request, cancellationToken)
```

- With our command it's doing something like this

```csharp
//request is an IRequest<CreateTicketResponse> from the non-generic
.Handle((CreateTicketCommand) request, cancellationToken)
```

- Now we are creating something like a function pointer to `.Handle()` with a lambda

```csharp
Task<TResponse> Handler() => 
```

At this point awaiting the Handler would wrap up our dispatch to `CreateTicketHandler`.  Let's back up one step and see how the instantiation of our handler with Dependency Injection went down in `RequestHandlerBase`.

```csharp
 protected static THandler GetHandler<THandler>(ServiceFactory factory)
 {
     THandler handler;
     try
     {
        handler = factory.GetInstance<THandler>();
     }
```

I expected more code.  Let's take a look at `ServiceFactory` to see what's up.

```csharp
public delegate object ServiceFactory(Type serviceType);

public static class ServiceFactoryExtensions
{
    public static T GetInstance<T>(this ServiceFactory factory)
        => (T) factory(typeof(T));

    public static IEnumerable<T> GetInstances<T>(this ServiceFactory factory)
            => (IEnumerable<T>) factory(typeof(IEnumerable<T>));
}
```

**Mind Blown!** `ServiceFactory` is just a delegate.  Beyond that the method `GetInstance<THandler>` is an extension method on the delegate.  It turns out that <mark>C# supports extension methods on delegates</mark>.  Essentially, `ServiceFactory` is a single method facade over our Dependency Injection container.  The only burden `ServiceFactory` puts on the underlying container is to have a method that takes in a `Type`.  Then with a couple of extension methods we overlay a nicer generic interface `T GetInstance<T>` and `IEnumerable<T> GetInstances<T>`.  You don't see this kind of one-liner magic in C# every day.  

<mark>MediatR's support for all the different dependency injection frameworks boils down to a simple one line delegate</mark>.  Ironically, if you look into one of the Dependency Injection integrations like [MediatR.Extensions.Microsoft.DependencyInjection](https://github.com/jbogard/MediatR.Extensions.Microsoft.DependencyInjection/blob/master/src/MediatR.Extensions.Microsoft.DependencyInjection/Registration/ServiceRegistrar.cs), it takes about as much code registering all the bells and whistles related to handlers as all of MediatR.  

