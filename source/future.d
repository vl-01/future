module future;

import core.thread;
import std.concurrency : spawn;
import std.experimental.logger;
import std.typetuple;
import std.functional : compose;
import std.typecons;
import std.traits;
import std.range;
import std.algorithm;
import std.format;
import std.conv;
import universal;
import universal.extras;
import universal.meta;;

alias defaultWait = Thread.yield;

static:

template Future(A, alias f)
{
  final shared class Future
  {
    alias Result = A;

    private:
    void delegate(A)[] _onFulfill;
    A _result;
    bool _ready;
  }
}
alias Future(A) = Future!(A, identity);
enum isFuture(F) = is(F == Future!(A,f), A, alias f);

template pending(A, alias f)
{
  shared(Future!(A,f)) pending()
  { return new typeof(return); }
}
template result(A, alias f)
{
  A result(shared(Future!(A,f)) future) 
  in{ assert(future.isReady); }
  body{ return *cast(A*)&future._result; }
}
template fulfill(B, alias f, A...)
{
  shared(Future!(B,f)) fulfill(shared(Future!(B,f)) future, A args)
  {
      synchronized(future)
        if(future.isReady)
          return future;
        else
        {
          *cast(B*)&future._result = apply!f(args);
          future._ready = true;
        }

      foreach(cb; future._onFulfill)
        cb(future.result);

      future._onFulfill = [];

      return future;
  }
}
template onFulfill(B, alias f)
{
  void onFulfill(shared(Future!(B,f)) future, void delegate(B) callback)
  {
    synchronized(future)
      if(future.isReady) // REVIEW could this lead to a race condition? can that be analyzed with π calculus?
        callback(future.result);
      else
        future._onFulfill ~= callback;
  }
}

alias pending(A) = pending!(A,    identity);
alias pending()  = pending!(Unit, identity);

template isReady(A, alias f)
{
  bool isReady(shared(Future!(A,f)) future)
  { return future._ready; }
}
template isPending(A, alias f)
{
  bool isPending(shared(Future!(A,f)) future)
  { return ! future.isReady; }
}

template async(alias f) // applied
{
  template async(A...)
  {
    alias g = tryCatch!f;
    alias B = typeof(g(A.init));

    static void run(shared(Future!(B,g)) future, A args)
    { future.fulfill(args); }

    shared(Future!(B,g)) async(A args)
    {
      auto future = pending!(B,g);

      spawn(&run, future, args);

      return future;
    }
  }
}
template await(alias wait = defaultWait)
{
  template await(A, alias f)
  {
    shared(Future!(A,f)) await(shared(Future!(A,f)) future)
    {
      while(future.isPending)
        wait();

      return future;
    }
  }
}

template next(alias f) // applied
{
  template next(A, alias g, C...)
  {
    alias B = typeof(apply!f(A.init, C.init).result);

    shared(Future!B) next(shared(Future!(A,g)) future, C args)
    { return future.then!f(args).sync; }
  }
}
template sync(A, alias f, alias g)
{
  shared(Future!A) sync(shared(Future!(shared(Future!(A,f)), g)) future)
  {
    auto synced = pending!A;

    future.onFulfill((shared(Future!(A,f)) nextFuture)
    { nextFuture.onFulfill((A a){ synced.fulfill(a); }); }
    );

    return synced;
  }
}
template then(alias f) // applied
{
  template then(A, alias g, B...)
  {
    alias C = typeof(apply!f(A.init, B.init));

    shared(Future!(C,f)) then(shared(Future!(A,g)) future, B args)
    {
      auto thenFuture = pending!(C,f);

      future.onFulfill((A result)
      { thenFuture.fulfill(result, args); }
      );

      return thenFuture;
    }
  }
}
template when(futureNames...) if(allSatisfy!(isString, futureNames)) // names are optional
{
  template when(Futures...) if(allSatisfy!(isFuture, Futures))
  {
    alias Result(F) = typeof(F.init.result());
    alias Types = staticMap!(Result, Futures);
    alias When = Tuple!(DeclSpecs!(Types, futureNames));

    shared(Future!When) when(Futures futures)
    {
      auto allFuture = pending!When;

      foreach(i, future; futures[])
        future.onFulfill((Types[i])
        {
          if(all(futures.t_.tlift!isReady[].only))
            allFuture.fulfill(futures.t_.tlift!result);
        }
        );

      return allFuture;
    }
  }
}
template race(futureNames...) if(allSatisfy!(isString, futureNames)) // names are optional
{
  template race(Futures...) if(allSatisfy!(isFuture, Futures))
  {
    alias Result(F) = typeof(F.init.result());
    alias Types = staticMap!(Result, Futures);
    alias Race = Union!(DeclSpecs!(futureNames, Types));

    shared(Future!Race) race(Futures futures)
    {
      auto anyFuture = pending!Race;

      foreach(i, future; futures[])
        future.onFulfill((Types[i] result)
        { anyFuture.fulfill(Race().inject!i(result)); }
        );

      return anyFuture;
    }
  }
}

@("EXAMPLES") unittest
{
  /*
    basic usage
  */
  auto ex1 = pending!int;
  assert(ex1.isPending);
  ex1.fulfill(6);
  assert(ex1.isReady);
  assert(ex1.result == 6);

  /*
    then: mapping over futures
  */
  auto ex2a = pending!int;
  auto ex2b = ex2a.then!((int x) => x * 2);
  assert(ex2a.isPending && ex2b.isPending);
  ex2a.fulfill(3);
  assert(ex2a.isReady && ex2b.isReady);
  assert(ex2b.result == 6);

  /*
    when: maps a tuple of futures to a future tuple 
      completes when all complete
  */
  auto ex3a = pending!int;
  auto ex3b = pending!int;
  auto ex3c = pending!int;
  auto ex3 = when(ex3a, ex3b, ex3c);
  assert(ex3.isPending);
  ex3a.fulfill = 1;
  ex3b.fulfill = 2;
  assert(ex3.isPending);
  ex3c.fulfill = 3;
  assert(ex3.isReady);
  assert(ex3.result == tuple(1,2,3));

  /*
    race: maps a tuple of futures to a future union
      inhabited by the first of the futures to complete
  */
  auto ex4a = pending!int;
  auto ex4b = pending!(Tuple!(int, int));
  auto ex4 = race(ex4a, ex4b);
  assert(ex4.isPending);
  ex4b.fulfill(1,2);
  assert(ex4.isReady);
  assert(ex4.result.visit!(
    (x) => x,
    (x,y) => x + y
  ) == 3);

  /*
    note: when and race can both accept named fields as template arguments
  */

  /*
    async/await: multithreaded function calls
  */
  auto ex5a = tuple(3, 2)[].async!((int x, int y) 
  { Thread.sleep(250.msecs); return x * y; }
  );
  assert(ex5a.isPending);
  ex5a.await;
  assert(ex5a.isReady);
  /*
    async will wrap the function's return value in a Result (see universal.extras.errors)
  */
  assert(ex5a.result.visit!(
    q{failure}, _ => 0,
    q{success}, x => x,
  ) == 6);
  /*
    which allows errors and exceptions to be easily recovered
    whereas normally, if a thread throws, it dies silently.
  */
  auto ex5b = async!((){ throw new Exception("!"); });
  auto ex5c = async!((){ assert(0, "!"); });
  assert(ex5b.await.result.failure.exception.msg == "!");
  assert(ex5c.await.result.failure.error.msg == "!");
  /*
    by the way, functions that return void can have their result visited with no arguments
  */
  assert(async!((){}).await.result.visit!(
    q{failure}, _ => false,
    q{success}, () => true,
  ));

  /*
    sync: flattens nested futures into one future
      the new future waits until both nested futures are complete
      then forwards the result from the inner future
  */
  auto ex6a = pending!(shared(Future!(int)));
  auto ex6 = sync(ex6a);
  assert(ex6.isPending);
  ex6a.fulfill(pending!int);
  assert(ex6.isPending);
  ex6a.result.fulfill(6);
  assert(ex6.isReady);
  assert(ex6.result == 6);

  /*
    next: chains the fulfillment of one future into the launching of another
      enables comfortable future sequencing
  */
  auto ex7a = pending!(int);
  auto ex7b = ex7a.next!(async!((int i) => i));
  auto ex7c = ex7a.then!(async!((int i) => i));
  assert(ex7b.isPending && ex7c.isPending);
  ex7a.fulfill(6);
  ex7b.await; ex7c.await;
  assert(ex7b.isReady && ex7c.isReady);
  assert(ex7a.result == 6);
  assert(ex7b.result.success == 6);
  assert(ex7c.result.await.result.success == 6);
}