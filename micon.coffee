try
  try
    # Trying synchronize first if it's installed.
    Fiber = require('synchronize').Fiber
  catch err
    Fiber = require 'fibers'
catch err
  # Fiber required for `fiber` and custom scopes. Allowing to fall
  # back and use limited functionality when fibers not available.
  console.warn "fibers not available!"
  Fiber = {}

# Helpers.
isFunction = (o) -> typeof(o) == 'function'
extend     = (a, b) ->
  a[k] = v for own k, v of b
  a
cloneOneLevelDeep = (o) ->
  if Array.isArray o then (v for v in o)
  else extend({}, o)

# # Micon, dependency injector.
Micon = -> @initialize.apply(@, arguments); @

# Initialization.
Micon::initialize = -> @clear()

# Creates scope, provided `callback` will be executed within that scope.
Micon::scope = (scopeName, container..., callback) ->
  container = container[0] || {}

  throw new Error "no callback for scope '#{scopeName}'!" unless scopeName
  return callback() if scopeName in ['global', 'application', 'instance']
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
    when 'application' then true
    when 'global'      then true
    when 'fiber'       then Fiber.current?
    when 'instance'    then true
    else
      if activeScopes = Fiber.current?.activeScopes then scopeName of activeScopes
      else false

# Clear everything.
Micon::clear = ->
  [@registry, @initializers] = [{}, {}]
  @applicationComponents = {}
  [@beforeCallbacks, @afterCallbacks] = [[], []]
  [@beforeScopeCallbacks, @afterScopeCallbacks] = [[], []]
  # @injectedClasses = []
Micon.clear = ->
  @activeInitializations = {}
  @globalComponents      = {}
Micon.clear()

Micon::clone = (name = 'clone') ->
  clone = new Micon()

  # Copying properties.
  extend clone, @
  clone.clear()

  # Copying comlex objects.
  complexObjects = ['registry', 'initializers', 'beforeCallbacks', 'afterCallbacks'
  , 'beforeScopeCallbacks', 'afterScopeCallbacks'] # , 'injectedClasses'
  clone[k] = cloneOneLevelDeep(@[k]) for k in complexObjects

  # Creating getters for components.
  clone.inject(clone, k) for k of clone.registry

  # # Creating getters for classes.
  # clone.injectClass(args...) for args in clone.injectedClasses
  clone.name = name
  clone

# Check if component instantiated.
Micon::has = (componentName) ->
  return false unless scopeName = @registry[componentName]

  switch scopeName
    when 'application' then componentName of @applicationComponents
    when 'global'      then componentName of Micon.globalComponents
    when 'fiber'
      if fiberComponents = Fiber.current?.fiberComponents then componentName of fiberComponents
      else false
    when 'instance'    then true
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
    when 'application'
      if component = @applicationComponents[componentName] then component
      else @_createComponent(componentName, @applicationComponents)
    when 'global'
      if component = Micon.globalComponents[componentName] then component
      else @_createComponent(componentName, Micon.globalComponents)
    when 'fiber'
      # Fiber scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      fiberComponents = (fiber.fiberComponents ?= {})
      if component = fiberComponents[componentName] then component
      else @_createComponent(componentName, fiberComponents)
    when 'instance' then @_createComponent componentName, {}
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
    when 'application'
      @applicationComponents[componentName] = component
      @_runAfterCallbacks componentName, component
      component
    when 'global'
      Micon.globalComponents[componentName] = component
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
    when 'instance'
      throw new Error "component '#{componentName}' has 'instance' scope, it can't be set!"
    else
      # Custom scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      unless container = fiber.activeScopes?[scopeName]
        throw new Error "can't get component '#{componentName}', scope '#{scopeName}' not created!"
      container[componentName] = component
      @_runAfterCallbacks componentName, component
      component

# Unset.
Micon::unset = (componentName) ->
  unless scopeName = @registry[componentName]
    throw new Error "component '#{componentName}' not registered!"

  switch scopeName
    when 'application' then delete @applicationComponents[componentName]
    when 'global'      then delete Micon.globalComponents[componentName]
    when 'fiber'
      # Fiber scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      fiberComponents = (fiber.fiberComponents ?= {})
      delete fiberComponents[componentName]
    when 'instance'
      throw new Error "component '#{componentName}' has 'instance' scope, it can't be unset!"
    else
      # Custom scope.
      unless fiber = Fiber.current
        throw new Error "can't get component '#{componentName}', no active fiber!"
      unless container = fiber.activeScopes?[scopeName]
        throw new Error "can't get component '#{componentName}', scope '#{scopeName}' not created!"
      delete container[componentName]

# Register component.
Micon::register = (componentName, args...) ->
  throw new Error "can't use '#{componentName}' as component name!" unless componentName
  initializer = args.pop() if args.length > 0 and isFunction(args[args.length - 1])
  options = args[0] || {}

  @registry[componentName]     = options.scope || 'application'
  @initializers[componentName] = [initializer, options.dependencies]

  # Injecting component so it will be available as property.
  @inject @, componentName

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

  if componentName of Micon.activeInitializations
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
    Micon.activeInitializations[componentName] = {}
    fiber.activeInitializations[componentName] = {} if fiber

    # Creating component.
    unless component = initializer()
      throw "initializer for component '#{componentName}' returns value evaluated to false!"

    # Setting link to self.
    component.app = @

    # Storing created component in container.
    container[componentName] = component
  finally
    delete Micon.activeInitializations[componentName]
    delete fiber.activeInitializations[componentName] if fiber

  @_runAfterCallbacks componentName, component
  component

# Inject component as a property into object.
Micon::inject = (object, componentNames...) ->
  that = @
  for componentName in componentNames
    do (componentName) ->
      Object.defineProperty object, componentName,
        get          :             -> that.get componentName
        set          : (component) -> that.set componentName, component
        configurable : true

Micon::inspect = -> @name || 'app'
Micon::toString = -> @name || 'app'

Micon::_runAfterCallbacks = (componentName, component) ->
  fn(component) for fn in list if list = @afterCallbacks[componentName]

Micon::_runBeforeCallbacks = (componentName) ->
  fn() for fn in list if list = @beforeCallbacks[componentName]

# # Autoloding.

# Require all files in directory, provide `onDemand: true` to load scripts
# on demand in form of `app.fileName`.
Micon.supportedExtensionsRe = /\.js$|\.coffee$/
Micon.watchInterval         = 500
Micon::requireDirectory = (directoryPath, options = {}) ->
  throw new Error "path '#{directoryPath}' should be absolute!" unless /^\//.test directoryPath

  # Collecting scripts in directory.
  fs = require 'fs'
  fileNames = fs.readdirSync directoryPath
  scripts = for fileName in fileNames when Micon.supportedExtensionsRe.test(fileName)
    filePath = "#{directoryPath}/#{fileName}"
    baseFileName = fileName.replace /\..+$/, ''
    baseFilePath = "#{directoryPath}/#{baseFileName}"
    [baseFileName, baseFilePath, filePath]

  # shouldBeDefined = (baseFileName) ->
  #   app[baseFileName] || throw new Error "wrong definition of '#{baseFileName}'!"
  eachScript = (fn) ->
    fn.apply null, script for script in scripts

  if options.onDemand
    # Load scripts in directory when it accessed as `app.fileName`.
    eachScript (baseFileName, baseFilePath, filePath) =>
      # @injectedClasses.push [baseFileName, baseFilePath, filePath]
      Object.defineProperty @, baseFileName,
        get          :         ->
          delete @[baseFileName]
          require baseFilePath
          # shouldBeDefined baseFileName
          @[baseFileName]
        set          : (value) ->
          delete @[baseFileName]
          @[baseFileName] = value
        configurable : true
  else
    # Loading directory, same as manually require every file in directory.
    eachScript (baseFileName, baseFilePath, filePath) ->
      require baseFilePath
      # shouldBeDefined baseFileName

  # Watching in development environment.
  if options.watch and @environment == 'development'
    eachScript (baseFileName, baseFilePath, filePath) =>
      fs.watchFile filePath, {interval: Micon.watchInterval}, (curr, prev) =>
        return if curr.mtime == prev.mtime
        console.info "  reloading #{baseFileName}"
        delete @[baseFileName]
        delete require.cache[filePath]
        require baseFilePath
        # shouldBeDefined baseFileName

# Environment.
Object.defineProperty Micon::, 'environment',
  get          :               ->
    @_environmentUsed = true
    @_environment || 'development'
  set          : (environment) ->
    throw new Error "can't set environment, itt's already used!" if @_environmentUsed
    @_environment = environment
  configurable : true

# Adding events.
try
  EventEmitter = require('events').EventEmitter
catch err
  # EventEmitter required for events. Allowing to fall
  # back and use limited functionality when fibers not available.
  EventEmitter = ->

# Mixing EventEmitter into Micon.
extend Micon::, EventEmitter::
Micon::initializeWithoutEventEmitter = Micon::initialize
Micon::initialize = ->
  @initializeWithoutEventEmitter.apply @, arguments
  EventEmitter.apply @

# Exporting.
if module?.exports? then module.exports = Micon else window.Micon = Micon