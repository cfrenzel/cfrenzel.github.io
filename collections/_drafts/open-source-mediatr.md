---
layout: post
title:  "Learning From Open Source Part1: MediatR"
author: camron
categories: [development]
image: assets/images/splash_benjamin-catapane.jpg
tags: [mediatR, tutorial]
---

It can be intimidating and time consuming to get familiar with a mature open source project.  Often an attempt to find inspiration just results in a surface level understanding of a few components with no real insight into the magic.  In this series I hope to find projects of just the right size and complexity to "get in there" and learn something.  Let's take a look a [MediatR](https://github.com/jbogard/MediatR).

I use MediatR in many projects because of its "simple to use" yet powerful implementation of the [Mediator Pattern](https://en.wikipedia.org/wiki/Mediator_pattern).  Essentially the mediator sits between method callers and receivers creating a configurable layer of abstraction that determines how callers and receivers get wired up.  

Let's look at a quick example of a Controller calling some Application Layer code.  


```csharp
public class TicketController: Controller
{
   private readonly IMediator_mediator;

    public SupplierController(IMediator mediator)
    {
        _mediator = mediator
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
- The `IMediator` is injected into the Controller
- There is a single `Send` method on the `IMediator` used to process all commands/messages types   
- The Controller has no idea who the receiver is

Here's a sample handler for <code>CreateTicketCommand</code>

```csharp
public class CreateTicketHandler : IRequestHandler<CreateTicketCommand, CreateTicketResponse>
{
    private readonly ApplicationDbContext _db;

    public Handler(ApplicationDbContext db) =>  _db = db;

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
- Handler has no idea who calls it
- Handler Implements a Generic `IRequestHandler<CreateTicketCommand, CreateTicketResponse>` that specifies the message type and return type
- Handler has constructor parameters that must be injected by the Mediator



We configure MediatR in our app's startup with a single line

- Adds MediatR to the container
- We tell it what assemblies all of our handlers are in and it wires up the commands/messages with the appropriate handlers

```csharp
  services.AddMediatR(mediatrAssemblies);
 ```

**The Source**

Let's dig in.  First download the source or browse online at [https://github.com/jbogard/MediatR/tree/master/src/MediatR](https://github.com/jbogard/MediatR/tree/master/src/MediatR)

<pre>
> git clone https://github.com/jbogard/MediatR.git .
</pre>

You'll first notice a handful of simple interfaces and the `Mediator.cs` class itself.  Skimming through `Mediator.cs` you may be surprised at how small the file is.  Our `Send` message is sitting right there in plane site

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


