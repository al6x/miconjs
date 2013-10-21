require './helper'

shared = (scope) ->
  it "should not allow to return null in component initializer", ->
    app.register 'component', scope: scope, -> null
    sync.fiber ->
      app.scope scope, ->
        expect(-> app.component).to.throw /null, false or empty string/

  it "should register component without initializer but not create it", ->
    app.register 'component', scope: scope
    sync.fiber ->
      app.scope scope, ->
        expect(-> app.component).to.throw /no initializer/

  it "should not allow to set null as component", ->
    app.register 'component', scope: scope
    sync.fiber ->
      app.scope scope, ->
        expect(-> app.component = null).to.throw /can't set .* component/

  it "should set link to self on component", ->
    app.register 'component', scope: scope, -> {name: 'some component'}
    sync.fiber ->
      app.scope scope, ->
        expect(app.component.app).to.equal app

describe "Application scope", ->
  shared 'instance'

describe "Global scope", ->
  shared 'global'

describe "Instance scope", ->
  shared 'instance'

describe "Custom scope", ->
  shared 'custom'

  it "should not ativate scope twice", ->
    sync.fiber ->
      app.scope 'custom', {}, ->
        expect(-> app.scope 'custom').to.throw /already active/

  it "shoud not get or set component if scope isn't active", ->
    app.register 'component', scope: 'custom', -> 'some component'
    sync.fiber ->
      expect(-> app.component).to.throw /scope.*not created/
      expect(-> app.component = 'other component').to.throw /scope.*not created/

  it "should not activate scope without active fiber"

describe "Fiber scope", ->
  shared 'fiber'

  it "shoud not get or set component if scope isn't active", ->
    app.register 'component', scope: 'fiber', -> 'some component'
    expect(-> app.component).to.throw /no active fiber/
    expect(-> app.component = 'other component').to.throw /no active fiber/

  it "should not activate scope without active fiber"

  it "should resolve asynchronous initialization", (next) ->
    app.register 'db', ->
      process.nextTick sync.defer()
      sync.await()
      'some db'

    sync.fiber ->
      expect(app.db).to.eql 'some db'
      next()

  it "should resolve asynchronous initialization in case of concurrent access", (next) ->
    events = []
    app.register 'db', ->
      events.push 'initializing db'
      process.nextTick sync.defer()
      sync.await()
      'some db'

    done = (name) ->
      done[name] = true
      if done.a and done.b
        expect(events).to.eql ['initializing db']
        next()

    sync.fiber ->
      expect(app.db).to.eql 'some db'
      done 'a'

    sync.fiber ->
      expect(app.db).to.eql 'some db'
      done 'b'


  # it "should store components in container", ->
  #   app.register 'component', scope: 'custom', -> ['some component']
  #   [container, component] = [{}, null]
  #
  #   app.activate 'custom', container, ->
  #     expect(app.component).to.eql ['some component']
  #     component = app.component
  #
  #   app.activate 'custom', ->
  #     expect(app.component).to.not.equal component
  #
  #   app.activate 'custom', container, ->
  #     expect(app.component).to.equal component
  #
  #   expect(_(container).size()).to.eql 1
  #   expect(container.component).to.equal component
  #
  #   app.activate 'custom', container, ->
  #     app.component = 'another component'
  #   expect(container.component).to.eql 'another component'

describe "Circullar dependencies", ->
  it  "should not allow circular dependency for single component", ->
    app.register 'component', ->
      app.component
      'component'
    expect(-> app.component).to.throw /component .* used before its initialization finished/

  it "should allow to use circullar dependency in after callback for single component", ->
    app.register 'component', -> {name: 'component'}
    app.after 'component', -> app.component.altered = true
    expect(app.component).to.have.property('name').to.eql 'component'
    expect(app.component).to.have.property('altered').to.eql true

  it "should not allow circular dependency for multiple components", ->
    app.register 'environment', ->
      app.router
      'environment'

    app.register 'router', ->
      app.environment
      'router'

    expect(-> app.router).to.throw /component .* used before its initialization finished/

  it "should allow circullar dependency in after callback for multiple components", ->
    app.register 'environment', -> 'environment'
    app.after 'environment', -> app.router

    app.register 'router', dependencies: ['environment'], -> 'router'

    app.router

describe "Component callbacks", ->
  it "should fire after callbacks when manually setting component", ->
    app.register 'component'
    events = []
    app.before 'component', -> events.push 'before'
    app.after 'component', ->
      expect(app.component).to.eql 'some component'
      events.push 'after'

    app.component = 'some component'
    expect(events).to.eql ['after']

  it "should fire after callback immediately if it's defined after component is created", ->
    app.register 'component', -> 'some component'
    app.component
    events = []
    app.before 'component', -> events.push 'before'
    app.after 'component', -> events.push 'after'
    expect(events).to.eql ['after']

  # it ":after with bang: false should execute callback if component already started and also register it as :after callback" do
  #   app.register(:the_component){"the_component"}
  #   app[:the_component]
  #
  #   check = mock
  #   check.should_receive(:first).twice
  #   app.after(:the_component, bang: false){check.first}
  #
  #   app.delete :the_component
  #   app[:the_component]

describe "Scope callbacks", ->
  it "should raise error if callback defined after scope already started", ->
    sync.fiber ->
      app.scope 'custom', ->
        expect(-> app.beforeScope 'custom').to.throw /already created/
        expect(-> app.afterScope 'custom').to.throw /already created/

describe "Cloning", ->
  it "should clone", ->
    app.register 'component', -> {name: 'some component'}
    expect(app.component).to.have.property('name').to.eql 'some component'
    app2 = app.clone()
    expect(app2.component).to.have.property('name').to.eql 'some component'
    expect(app.component).to.not.equal app2.component

  it "should be isolated", ->
    app.register 'component', -> {name: 'some component'}
    app2 = app.clone()
    app2.register 'component', -> {name: 'another component'}
    expect(app.component).to.have.property('name').to.eql 'some component'
    expect(app2.component).to.have.property('name').to.eql 'another component'

  it "should share global scope", ->
    app.register 'component', scope: 'global', -> {name: 'some component'}
    expect(app.component).to.have.property('name').to.eql 'some component'
    app2 = app.clone()
    expect(app2.component).to.have.property('name').to.eql 'some component'
    expect(app.component).to.equal app2.component