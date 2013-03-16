# Fiber required for `fiber` and custom scopes, allowing to fall back and use limited
# functionality when fibers not available.
try
  Fiber = require 'fibers'
catch err

# Helpers.
isFunction = (o) -> typeof(o) == 'function'

# Micon, dependency injector.
Micon  = -> @initialize.apply(@, arguments); @
mproto = Micon.prototype

# Initialization.
mproto.initialize = -> @clear()

# Creates scope, provided `callback` will be executed within that scope.
mproto.scope = (scopeName, container..., callback) ->
  container = container[0] || {}

  throw new Error "no callback for scope '#{scopeName}'!" unless scopeName
  return callback() if scopeName in ['static', 'instance']
  unless fiber = Fiber.current
    throw new Error "can't activate scope '#{scopeName}' without fiber!"
  fiber.activeScopes ?= {}
  throw new Error "scope '#{scopeName}' already active!" if scopeName of fiber.activeScopes

  try
    # Triggering before scope callbacks.
    fn() for fn in list if list = @beforeScopeCallbacks[scopeName]
    # Running scope.
    fiber.activeScopes[scopeName] = container
    callback()
    # Triggering after scope callback.
    fn() for fn in list if list = @afterScopeCallbacks[scopeName]
  finally
    delete fiber.activeScopes[scopeName]
  container

# Check if scope created.
mproto.hasScope = (scopeName) ->
  switch scopeName
    when 'instance' then true
    when 'static'   then true
    when 'fiber'    then Fiber.current?
    else
      if activeScopes = Fiber.current?.activeScopes then scopeName of activeScopes
      else false

# Clear everything.
mproto.clear = ->
  [@registry, @initializers] = [{}, {}]
  @staticComponents = {}
  [@beforeCallbacks, @afterCallbacks] = [[], []]
  [@beforeScopeCallbacks, @afterScopeCallbacks] = [[], []]
  @activeInitializations = {}

# Check if component instantiated.
mproto.has = (componentName) ->
  return false unless scopeName = @registry[componentName]

  switch scopeName
    when 'instance' then true
    when 'static'   then componentName of @staticComponents
    when 'fiber'
      if fiberComponents = Fiber.current?.fiberComponents then componentName of fiberComponents
      else false
    else
      # Custom scope.
      if (activeScopes = Fiber.current?.activeScopes) and (container = activeScopes[scopeName])
        componentName of container
      else false

# Get component.
mproto.get = (componentName) ->
  unless scopeName = @registry[componentName]
    throw new Error "component '#{componentName}' not registered!"

  switch scopeName
    when 'instance' then @_createComponent componentName
    when 'static'
      if component = @staticComponents[componentName] then component
      else @_createComponent(componentName, @staticComponents)
    when 'fiber'
      # Fiber scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      fiberComponents = (fiber.fiberComponents ?= {})
      if component = fiberComponents[componentName] then component
      else @_createComponent(componentName, fiberComponents)
    else
      # Custom scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      unless container = fiber.activeScopes?[scopeName]
        throw new Error "can't get component '#{componentName}', scope '#{scopeName}' not created!"

      if component = container[componentName] then component
      else @_createComponent(componentName, container)

# Set component.
mproto.set = (componentName, component) ->
  unless scopeName = @registry[componentName]
    throw new Error "component '#{componentName}' not registered!"
  throw new Error "can't set '#{componentName}' component as '#{component}'!" unless component

  switch scopeName
    when 'instance'
      throw new Error "component '#{componentName}' has 'instance' scope, it can't be set!"
    when 'static'
      @staticComponents[componentName] = component
      @_runAfterCallbacks componentName
      component
    when 'fiber'
      # Fiber scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      fiberComponents = (fiber.fiberComponents ?= {})
      fiberComponents[componentName] = component
      @_runAfterCallbacks componentName
      component
    else
      # Custom scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      unless container = fiber.activeScopes?[scopeName]
        throw new Error "can't get component '#{componentName}', scope '#{scopeName}' not created!"
      container[componentName] = component
      @_runAfterCallbacks componentName
      component

# Register component.
mproto.register = (componentName, args...) ->
  throw new Error "can't use '#{componentName}' as component name!" unless componentName
  initializer = args.pop() if args.length > 0 and isFunction(args[args.length - 1])
  options = args[0] || {}

  @registry[componentName]     = options.scope || 'static'
  @initializers[componentName] = [initializer, options.dependencies]

  # Injecting component so it will be available as property.
  @inject componentName, Micon

# Check if component registered.
mproto.isRegistered = (componentName) -> componentName of @registry

# Callback triggered before component initialized.
mproto.before = (componentName, callback) ->
  throw new Error "component '#{componentName}' already created!" if @has componentName
  (@beforeCallbacks[componentName] ?= []).push callback

# Callback triggered after component initialized.
mproto.after = (componentName, callback) ->
  throw new Error "component '#{componentName}' already created!" if @has componentName
  (@afterCallbacks[componentName] ?= []).push callback

# Callback triggered before scope created.
mproto.beforeScope = (scopeName, callback) ->
  throw new Error "scope '#{scopeName}' already created!" if @hasScope scopeName
  (@beforeScopeCallbacks[scopeName] ?= []).push callback

# Callback triggered after scope created.
mproto.afterScope = (scopeName, callback) ->
  throw new Error "scope '#{scopeName}' already created!" if @hasScope scopeName
  (@afterScopeCallbacks[scopeName] ?= []).push callback

# Creates component.
mproto._createComponent = (componentName, container) ->
  [initializer, dependencies] = @initializers[componentName]

  unless initializer
    throw new Error "no initializer for '#{componentName}' component!"

  if componentName of @activeInitializations
    throw new Error "component '#{componentName}' used before its initialization finished!"

  # Initialising dependencies.
  @get(name) for name in dependencies if dependencies

  # Triggering before callbacks.
  @_runBeforeCallbacks componentName

  try
    # We need this check to detect and prevent component from been used before its initialization
    # finished.
    @activeInitializations[componentName] = true

    # We need to check container first, in complex cases (circullar dependency)
    # the object already may be initialized.
    # See "should allow to use circullar dependency in after callback".
    return component if component = (container && container[componentName])

    unless component = initializer()
      throw "initializer for component '#{componentName}' returns value evaluated to false!"

    # Storing created component in container.
    container[componentName] = component if container
  finally
    delete @activeInitializations[componentName]

  @_runAfterCallbacks componentName
  component

# Inject component as a property into object.
mproto.inject = (componentName, klass) ->
  Object.defineProperty klass.prototype, componentName,
    set          : (component) -> app.set componentName, component
    get          :         -> app.get componentName
    configurable : true

mproto._runAfterCallbacks = (componentName) ->
  fn() for fn in list if list = @afterCallbacks[componentName]

mproto._runBeforeCallbacks = (componentName) ->
  fn() for fn in list if list = @beforeCallbacks[componentName]

# Setting global `app` variable.
(global || window).app = new Micon()