try
  Fiber = require 'fibers'
catch err
  # Fiber required for `fiber` and custom scopes, allowing to fall back and use limited
  # functionality when fibers not available.
  Fiber = {}

# Helpers.
isFunction = (o) -> typeof(o) == 'function'

# # Micon, dependency injector.
Micon  = -> @initialize.apply(@, arguments); @

# Initialization.
Micon::initialize = -> @clear()

# Creates scope, provided `callback` will be executed within that scope.
Micon::scope = (scopeName, container..., callback) ->
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
    fn(container) for fn in list if list = @afterScopeCallbacks[scopeName]
  finally
    delete fiber.activeScopes[scopeName]
  container

# Check if scope created.
Micon::hasScope = (scopeName) ->
  switch scopeName
    when 'instance' then true
    when 'static'   then true
    when 'fiber'    then Fiber.current?
    else
      if activeScopes = Fiber.current?.activeScopes then scopeName of activeScopes
      else false

# Clear everything.
Micon::clear = ->
  [@registry, @initializers] = [{}, {}]
  @staticComponents = {}
  [@beforeCallbacks, @afterCallbacks] = [[], []]
  [@beforeScopeCallbacks, @afterScopeCallbacks] = [[], []]
  @activeInitializations = {}

# Check if component instantiated.
Micon::has = (componentName) ->
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
Micon::get = (componentName) ->
  unless scopeName = @registry[componentName]
    throw new Error "component '#{componentName}' not registered!"

  switch scopeName
    when 'instance' then @_createComponent componentName, {}
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
Micon::set = (componentName, component) ->
  unless scopeName = @registry[componentName]
    throw new Error "component '#{componentName}' not registered!"
  throw new Error "can't set '#{componentName}' component as '#{component}'!" unless component

  switch scopeName
    when 'instance'
      throw new Error "component '#{componentName}' has 'instance' scope, it can't be set!"
    when 'static'
      @staticComponents[componentName] = component
      @_runAfterCallbacks componentName, component
      component
    when 'fiber'
      # Fiber scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      fiberComponents = (fiber.fiberComponents ?= {})
      fiberComponents[componentName] = component
      @_runAfterCallbacks componentName, component
      component
    else
      # Custom scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      unless container = fiber.activeScopes?[scopeName]
        throw new Error "can't get component '#{componentName}', scope '#{scopeName}' not created!"
      container[componentName] = component
      @_runAfterCallbacks componentName, component
      component

# Register component.
Micon::register = (componentName, args...) ->
  throw new Error "can't use '#{componentName}' as component name!" unless componentName
  initializer = args.pop() if args.length > 0 and isFunction(args[args.length - 1])
  options = args[0] || {}

  @registry[componentName]     = options.scope || 'static'
  @initializers[componentName] = [initializer, options.dependencies]

  # Injecting component so it will be available as property.
  @inject Micon, componentName

# Check if component registered.
Micon::isRegistered = (componentName) -> componentName of @registry

# Callback triggered before component initialized.
Micon::before = (componentName, callback) ->
  # throw new Error "component '#{componentName}' already created!" if @has componentName
  (@beforeCallbacks[componentName] ?= []).push callback

# Callback triggered after component initialized.
Micon::after = (componentName, callback) ->
  # throw new Error "component '#{componentName}' already created!" if @has componentName
  callback @get(componentName) if @has componentName
  (@afterCallbacks[componentName] ?= []).push callback

# Callback triggered before scope created.
Micon::beforeScope = (scopeName, callback) ->
  throw new Error "scope '#{scopeName}' already created!" if @hasScope scopeName
  (@beforeScopeCallbacks[scopeName] ?= []).push callback

# Callback triggered after scope created.
Micon::afterScope = (scopeName, callback) ->
  throw new Error "scope '#{scopeName}' already created!" if @hasScope scopeName
  (@afterScopeCallbacks[scopeName] ?= []).push callback

# Creates component.
Micon.asynchronousInitializationTimeout = 1500
Micon.asynchronousInitializationInterval = 5
Micon::_createComponent = (componentName, container) ->
  [initializer, dependencies] = @initializers[componentName]

  unless initializer
    throw new Error "no initializer for '#{componentName}' component!"

  # Current fiber needed to resolve concurrent acces in asynchronous initializations.
  fiber.activeInitializations ?= {} if fiber = Fiber.current

  if componentName of @activeInitializations
    if fiber and not (componentName of fiber.activeInitializations)
      # Multiple fibers trying to get access to asynchronously initialized
      # component. See `should resolve asynchronous initialization in
      # case of concurrent access` for details.
      #
      # Waiting when initialization will be finished or timeout exeeded.
      startTime = Date.now()
      while Date.now() - startTime < Micon.asynchronousInitializationTimeout
        setTimeout (-> fiber.run()), Micon.asynchronousInitializationInterval
        Fiber.yield()
        return component if component = container[componentName]
      throw new Error \
      "failed to resolve concurrent initialization of asynchronous '#{componentName}' component!"
    else
      throw new Error "component '#{componentName}' used before its initialization finished!"

  # Initialising dependencies.
  @get(name) for name in dependencies if dependencies

  # Component may be initialized in dependencies, returning it.
  return component if component = container[componentName]

  # Triggering before callbacks.
  @_runBeforeCallbacks componentName

  try
    # We need this check to detect and prevent component from been used before its initialization
    # finished.
    @activeInitializations[componentName] = {}
    fiber.activeInitializations[componentName] = {} if fiber

    unless component = initializer()
      throw "initializer for component '#{componentName}' returns value evaluated to false!"

    # Storing created component in container.
    container[componentName] = component
  finally
    delete @activeInitializations[componentName]
    delete fiber.activeInitializations[componentName] if fiber

  @_runAfterCallbacks componentName, component
  component

# Inject component as a property into object.
Micon::inject = (klass, componentName) ->
  Object.defineProperty klass::, componentName,
    get          :             -> app.get componentName
    set          : (component) -> app.set componentName, component
    configurable : true

Micon::_runAfterCallbacks = (componentName, component) ->
  fn(component) for fn in list if list = @afterCallbacks[componentName]

Micon::_runBeforeCallbacks = (componentName) ->
  fn() for fn in list if list = @beforeCallbacks[componentName]

# # Autoloding.

# Require all files in directory, provide `onDemand: true` to load scripts in
# form of `app.fileName` on demand.
Micon.supportedExtensionsRe = /\.js$|\.coffee$/
Micon::requireDirectory = (directoryPath, options = {}) ->
  throw new Error "path '#{directoryPath}' should be absolute!" unless /^\//.test directoryPath

  _eachScriptInDirectory = (directoryPath, fn) ->
    fs = require 'fs'
    fileNames = fs.readdirSync directoryPath
    for fileName in fileNames when Micon.supportedExtensionsRe.test(fileName)
      filePath = "#{directoryPath}/#{fileName}"
      baseFileName = fileName.replace /\..+$/, ''
      baseFilePath = "#{directoryPath}/#{baseFileName}"
      fn baseFileName, baseFilePath, filePath

  # Load scripts in directory when it accessed as `app.fileName`.
  requireDirectoryOnDemand = ->
    _eachScriptInDirectory directoryPath, (baseFileName, baseFilePath, filePath) ->
      Object.defineProperty Micon::, baseFileName,
        get          :         ->
          delete Micon::[baseFileName]
          require(baseFilePath)
          @[baseFileName] || throw new Error "wrong definition of '#{baseFileName}'!"
        set          : (value) ->
          delete Micon::[baseFileName]
          @[baseFileName] = value
        configurable : true

  # Loading directory, same as manually require every file in directory.
  requireDirectoryNow = ->
    _eachScriptInDirectory directoryPath, (baseFileName, baseFilePath, filePath) ->
      require baseFilePath

  if options.onDemand then requireDirectoryOnDemand() else requireDirectoryNow()

# Environment.
Object.defineProperty Micon::, 'environment',
  get          :               ->
    @_environmentUsed = true
    @_environment
  set          : (environment) ->
    throw new Error "can't set environment, itt's already used!" if @_environmentUsed
    @_environment = environment
  configurable : true

# # Default configuration.
app = new Micon()
app.environment = 'development'

# Exposing dependency injector as global `app` variable.
((global? && global) || window).app = app