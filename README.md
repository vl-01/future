#future

## asynchronous combinator library for D

Futures are values yet to be computed. They are `shared`, and passively receive a pending value, and can actively forward the received value to callback delegates using `onFulfill`. For those inclined, these futures are functional, in that they expose 4 major functional patterns: functor, applicative, monoid, and monad.

## a common use case : executing a function in another thread

If `f :: A -> B`, then `async!f :: A -> Future!(Result!B)`. 
Suppose `f(a) = b` and `async!f(a) = c`.

`async!f` will execute `f` in a separate thread when invoked.

While `f` is being computed, `c.isPending`.

If `f` succeeds, `c.isReady` and `b == c.result.success`.

If `f` throws, `c.isReady` and `c.result.failure`.

Attempting to read `c.result` before `c.isReady` is an error.

`async!f` can be made blocking at any time with `c.await`.

For convenience, `c.await` returns `c` so that `c.await.result == c.result`.

## functional equivalences 

map = then

ap = apply . when
pure = fulfill . pending

append = race
empty = pending

bind = next
return = fulfill . pending
join = sync

## complete documentation:

```d
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
```
