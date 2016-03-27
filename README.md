#future

## asynchronous combinator library for D

Futures are values yet to be computed. They are `shared` and thread-safe. 

Futures receive a pending value with `fulfill`, and can actively forward the received value to callback delegates registered with `onFulfill`. 

## example: executing a function in another thread

If `f :: A -> B`, then `async!f :: A -> Future!(Result!B)`. 

Suppose `f(a) = b` and `async!f(a) = c`.

`async!f` will execute `f` in a separate thread when invoked.

While `f` is being computed, `c.isPending`.

If `f` succeeds, `c.isReady` and `b == c.result.success`.

If `f` throws, `c.isReady` and `c.result.failure` is inhabited with the caught error.

Attempting to read `c.result` before `c.isReady` is an error.

`async!f` can be made blocking at any time with `c.await`.

For convenience, `c.await` returns `c` so that `c.await.result == c.result`.

## advanced usage

For a futures `a` and `b`, and arguments `c...`

`a.then!f(c)` returns a future which contains `f(a.result, c)` when `a` is ready

`a.next!f(c)` chains two futures (`a` and `f(a.result, c)`) into a single future

if `a.result` is also a future, `sync(a)` joins the inner and outer futures of `a` (like a lazy `await.result.await`)

`when(a,b)` is a future `Tuple(a.result, b.result)`, ready when both `a` and `b` are ready

`race(a,b)` is a future `Union(a.result, b.result)`, ready when either `a` or `b` are ready

## detailed documentation and examples

is contained in the `unittest`

## with dub

`dependency "future" version="0.1.0"`
