Dependency injector, assembles application.

Registering, getting and setting components.

``` CoffeeScript
app.register 'component', -> 'some component'
console.log app.component
# => some component

app.component = 'another component'
console.log app.component
# => another component
```

Component lifecycle callbacks.

``` CoffeeScript
app.register 'component', ->
  console.log 'initialization'
  'some component'
app.before 'component', -> console.log 'before initialization'
app.after 'component', -> console.log 'after initialization'

app.component
# => before initialization
# => initialization
# => after initialization
```

Autoloading components from directory, same as manually
write `app.register 'something', -> require 'something'` for every file in
directory.

Provide `watch` option to reload on change.

``` CoffeeScript
app.register.directory directoryPath, watch: true
```

Scopes.

``` CoffeeScript
app.register 'params', scope: 'request', -> {}

startFiberSomehow ->
  app.activate 'request', ->
    app.params.key = 'some value'
    console.log app.params
    # => {key: 'some value'}
```

Scope callbacks.

``` CoffeeScript
app.beforeScope 'request', -> console.log 'before'
app.afterScope 'request', -> console.log 'after'

startFiberSomehow ->
  app.activate 'request', ->
  # => before
  # => after
```

Copyright (c) Alexey Petrushin, http://petrush.in, released under the MIT license.