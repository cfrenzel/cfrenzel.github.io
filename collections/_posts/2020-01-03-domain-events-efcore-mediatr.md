---
layout: post
title:  "Simple Domain Events with EFCore and MediatR"
author: camron
categories: [development]
image: assets/images/book-Evans_2004_ddd.jpg
tags: [featured, efcore, ddd, mediatR]
---

This post relates to the __Domain Driven Design (DDD)__ concept of __Domain Events__.  These events originate in the Domain Model and are broadcast within a Bounded Context.  These are not events used directly for integration.  For the purpose of this implementation I want to frame things as EFCore entities publishing events that can be handled locally by one or more subscribers within a Unit Of Work.  For more information about what Domain Events are/aren't and what they can be used for, check out [Domain Driven Design](https://www.amazon.com/exec/obidos/ASIN/0321125215/domainlanguag-20) by Eric Evans and [Implementing Domain Driven Design](https://www.oreilly.com/library/view/implementing-domain-driven-design/9780133039900/) by Vaughn Vernon.

Beyond the initial difficulty of understanding what Domain Events are, lies figuring out a way to implement the things.  How the heck can you cleanly publish an event from an Entity?  How would you wire up listeners, and where in the architecture would the listeners live?  Our entities are often in a core assembly that doesn't have any dependencies. There is no concept of a UnitOfWork/Transaction at this level, and they sure as heck don't have access to anything interesting like databases or an Application Layer where you might normally think about hydrating other entities and handling events.

This post describes a method to allow EFCore entities to publish Domain Events.  I've seen this technique used a handful of times, but to make this implementation a little more interesting Domain Events will be published as [MediatR](https://github.com/jbogard/MediatR) notifications that can be handled in the Application Layer.  In addition, this must be done without the entities taking on any external dependencies.  Specifically the entities won't have a dependency on MediatR.

Sound good? Let's get started!

<h4>The Entity side</h4>

The entity needs to call publish on something.  One of the simplest implementations from the entity's perspective is just to have the entity inherit from a base class that contains the publish logic.  In this implementation the entity won't actually be doing the event dispatching, it will just hold a collection of events that a dispatcher will later examine.

- First let's define an interface for the Entity

```csharp
using System;
using System.Collections.Concurrent;

namespace DomainEventsMediatR.Domain
{
    public interface IEntity
    {
        IProducerConsumerCollection<IDomainEvent> DomainEvents { get; }
    }
}

 public interface IDomainEvent { }
```


- Now a base class implementation for our EFCore entities marking the DomainEvents as <code>[NotMapped]</code> to let EFCore know that they are not to be persisted to the db. 

<div class="alert alert-primary">
 We also add a helper for entities to initialize there own Id's.  It can be very useful and efficient for entities to have their Id's generated locally "on or before instantiation" rather than "on save" or in the database.  This allows transient entities to reference eachother by Id, to store Id's in Domain Events, and generally to use Id's in all kinds of eventual consistency scenarios.  If you can't meet this requirement then you can pass the entity itself in the domain event, but remember that it hasn't been persisted yet; so you can't trust the transient Id assigned by EFcore (a new Id will be assigned by the database when persisted).
</div>

```csharp
using System;
using System.Collections.Concurrent;
using System.ComponentModel.DataAnnotations.Schema;

namespace DomainEventsMediatR.Domain
{ 
    public abstract class Entity : IEntity
    {     
        [NotMapped]
        private readonly ConcurrentQueue<IDomainEvent> _domainEvents = new ConcurrentQueue<IDomainEvent>();

        [NotMapped]
        public IProducerConsumerCollection<IDomainEvent> DomainEvents => _domainEvents;

        protected void PublishEvent(IDomainEvent @event)
        {
            _domainEvents.Enqueue(@event);
        }

        protected Guid NewIdGuid()
        {
            return MassTransit.NewId.NextGuid();
        }
    }
}
```
- Now a Domain Event: <code>BacklogItemCommitted</code> and an entity: <code>BacklogItem</code> that publishes the event when it is commited to a <code>Sprint</code>

```csharp
namespace DomainEventsMediatR.Domain
{
    public class BacklogItemCommitted : IDomainEvent
    {
        public Guid BacklogItemId { get; }
        public Guid SprintId { get; set; }
        public DateTime CreatedAtUtc { get; }

        private BacklogItemCommitted() { }

        public BacklogItemCommitted(BacklogItem b, Sprint s)
        {
            this.BacklogItemId = b.Id;
            this.CreatedAtUtc = b.CreatedAtUtc;
            this.SprintId = s.Id;
        }    
    }
}


using System;
using System.ComponentModel.DataAnnotations;

namespace DomainEventsMediatR.Domain
{
    public class BacklogItem : Entity
    {
        public Guid Id { get; private set; }

        [MaxLength(255)]
        public string Description { get; private set; }
        public virtual Sprint Sprint { get; private set; }
        public DateTime CreatedAtUtc { get; private set; } = DateTime.UtcNow;

        private BacklogItem() { }

        public BacklogItem(string desc)
        {
            this.Id = NewIdGuid();
            this.Description = desc;
        }
    
        public void CommitTo(Sprint s)
        {
            this.Sprint = s;
            this.PublishEvent(new BacklogItemCommitted(this, s));
        }
    }
}
```
- The real magic with this technique is how the Domain Events are dispatched.  Currently they're just sitting in the Entity.  We'll use some hooks in our DbContext to dispatch them, but first let's define an interface for the dispatcher

```csharp
using System.Threading.Tasks;

namespace DomainEventsMediatR.Domain
{
    public interface IDomainEventDispatcher
    {
        Task Dispatch(IDomainEvent devent);
    }
}
```

- Now we can configure the dispatcher to be injected into our DbContext constructor

```csharp
 public class ApplicationDbContext : DbContext
 {
    private readonly IDomainEventDispatcher _dispatcher;

    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options,
        IDomainEventDispatcher dispatcher)
        : base(options)
    {
        _dispatcher = dispatcher;
    }
```

- We can hook into EFCore and dispatch Domain Events before entities are persisted by overriding <code>SaveChanges</code>

```csharp
public override int SaveChanges()
{
    _preSaveChanges().GetAwaiter().GetResult();
    var res = base.SaveChanges();
    return res;
}

public override async Task<int> SaveChangesAsync(CancellationToken cancellationToken = default(CancellationToken))
{
    await _preSaveChanges();
    var res = await base.SaveChangesAsync(cancellationToken);
    return res;
}

private async Task _preSaveChanges()
{
    await _dispatchDomainEvents();
}

private async Task _dispatchDomainEvents()
{
    var domainEventEntities = ChangeTracker.Entries<IEntity>()
        .Select(po => po.Entity)
        .Where(po => po.DomainEvents.Any())
        .ToArray();

    foreach (var entity in domainEventEntities)
    {
        IDomainEvent dev;
        while (entity.DomainEvents.TryTake(out dev))
            await _dispatcher.Dispatch(dev);
    }
}
```

<h4>The Dispatcher</h4>
We need an implementation of <code>IDomainEventDispatcher</code> that will publish the Domain Event as a MediatR notification.  We'll implement this in our Application Layer.  We do have to deal with the small issue of our Domain Event not being a valid MediatR <code>INotification</code>.  We'll overcome this by creating a generic <code>INotification</code> to wrap our Domain Event.

- Create a custom generic <code>INotification</code>.

```csharp
using System;
using MediatR;
using DomainEventsMediatR.Domain;

namespace DomainEventsMediatR.Application
{
    public class DomainEventNotification<TDomainEvent> : INotification where TDomainEvent : IDomainEvent
    {
        public TDomainEvent DomainEvent { get; }

        public DomainEventNotification(TDomainEvent domainEvent)
        {
            DomainEvent = domainEvent;
        }
    }
}
```

- Create a Dispatcher that wraps Domain Events in MediatR notificatoins and publishes them

```csharp
using System;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using MediatR;
using DomainEventsMediatR.Domain;

namespace DomainEventsMediatR.Application
{
    public class MediatrDomainEventDispatcher : IDomainEventDispatcher
    {
        private readonly IMediator _mediator;
        private readonly ILogger<MediatrDomainEventDispatcher> _log;
        public MediatrDomainEventDispatcher(IMediator mediator, ILogger<MediatrDomainEventDispatcher> log)
        {
            _mediator = mediator;
            _log = log;
        }

        public async Task Dispatch(IDomainEvent devent)
        {

            var domainEventNotification = _createDomainEventNotification(devent);
            _log.LogDebug("Dispatching Domain Event as MediatR notification.  EventType: {eventType}", devent.GetType());
            await _mediator.Publish(domainEventNotification);
        }
       
        private INotification _createDomainEventNotification(IDomainEvent domainEvent)
        {
            var genericDispatcherType = typeof(DomainEventNotification<>).MakeGenericType(domainEvent.GetType());
            return (INotification)Activator.CreateInstance(genericDispatcherType, domainEvent);

        }
    }
}
```

- Create a handler for the <code>BacklogItemCommitted</code> Domain Event

```csharp
using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using MediatR;
using DomainEventsMediatR.Domain;
using DomainEventsMediatR.Persistence;

namespace DomainEventsMediatR.Application
{
    public class OnBacklogItemCommitted
    {
        public class Handler : INotificationHandler<DomainEventNotification<BacklogItemCommitted>>
        {
            private readonly ApplicationDbContext _db;
            private readonly ILogger<Handler> _log;
        
            public Handler(ApplicationDbContext db,  ILogger<Handler> log)
            {
                _db = db;
                _log = log;
            }

            public Task Handle(DomainEventNotification<BacklogItemCommitted> notification, CancellationToken cancellationToken)
            {
                var domainEvent = notification.DomainEvent;
                try
                {
                    _log.LogDebug("Handling Domain Event. BacklogItemId: {itemId}  Type: {type}", domainEvent.BacklogItemId, notification.GetType());
                    //from here you could 
                    // - create/modify entities within the same transaction as the backlogItem commit
                    // - trigger the publishing of an integration event on a servicebus (don't write it directly though, you need an outbox scoped to this transaction)
                                      
                    //Remember NOT to call SaveChanges on dbcontext if making db changes when handling DomainEvents
                    return Task.CompletedTask;
                }
                catch (Exception exc)
                {
                    _log.LogError(exc, "Error handling domain event {domainEvent}", domainEvent.GetType());
                    throw;
                }
            }
        }

    }
}
```

- Now we just need to configure dependency injection in our application and we're done

```csharp
     services.AddTransient<IDomainEventDispatcher, MediatrDomainEventDispatcher>();
     services.AddMediatR(typeof(MediatrDomainEventDispatcher).GetTypeInfo().Assembly);
```

You can find the full source code for this post at [https://github.com/cfrenzel/DomainEventsWithMediatR](https://github.com/cfrenzel/DomainEventsWithMediatR)