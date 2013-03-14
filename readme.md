Dependency injector, assembles application.

Registering and getting components.

``` CoffeeScript
app.register 'component', -> 'some component'
console.log app.component
# => some component

app.component = 'another component'
console.log app.component
# => another component
```

Autoloading components from directory, same as manually
write `app.register 'something', -> require 'something'` for every file in
directory.

Provide `watch` option to reload on change.

``` CoffeeScript
app.autoload directoryPath, watch: true
```

Custom scopes.

``` CoffeeScript
app.register 'session', scope: 'request', -> {}

somehowStartFiber ->
  app.activate 'request', ->
    app.session.key = 'some key'
    console.log app.session
    # => {key: 'some key'}
```

Copyright (c) Alexey Petrushin, http://petrush.in, released under the MIT license.