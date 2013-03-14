require './helper'

shared = (scope) ->
  it "should not allow to return null in component initializer", ->
    activateFiber ->
      app.activate scope, ->
        app.register 'component', scope: scope, -> null
        expect(-> app.component).should.throw /return null/

  it "should register component without initializer but not create it", ->
    activateFiber ->
      app.activate scope, ->
        app.register 'component', scope: scope,
        expect(-> app.component).to.throw /no initializer/

  it "should not allow to set null as component", ->
    activateFiber ->
      app.activate scope, ->
        app.register 'component', scope: scope
        expect(-> app.component).to.throw /can't set null/

describe "Instance scope", ->
  shared 'instance'

describe "Static scope", ->
  shared 'instance'

describe "Custom scope", ->
  shared 'custom'

  it "should not ativate scope twice", ->
    activateFiber ->
      app.activate 'custom', {}, ->
        expect(-> app.activate 'custom').to.throw /already active/

  it "shoud not get or set component if scope isn't active", ->
    app.register 'component', scope: 'custom', -> 'some component'
    expect(-> app.component).to.throw /scope.*not started/
    expect(-> app.component = 'other component').to.throw /scope.*not started/

  it "should not activate scope without active fiber"

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
  it "should not initialize twice", ->
    app.register 'component', ->
      app.component
      'component'
    expect(-> app.kit).to.throw /component .* used before its initialization finished/

  it "should not initialize twice if called from dependency", ->
    app.register 'environment', ->
      app.router
      'environment'

    app.register 'router', ->
      app.environment
      'router'

    expect(-> app.router).to.throw /component .* used before its initialization finished/

  it "should allow to use circullar dependency in after callback", ->
    app.register 'environment', -> 'environment'
    app.after 'environment', ->
      app.router

    app.register 'router', ->
      app.environment
      'router'

    app.router

describe "Component callbacks", ->
  it "should fire callbacks when manually setting component", ->
    app.register 'component'
    events = []
    app.before 'component', -> events.push 'before'
    app.after 'component', ->
      expect(app.component).to.eql 'some component'
      events.push 'after'

    app.component = 'some component'
    expect(events).to.eql ['before', 'after']

  it "should raise error if callback defined after component already created" do
    app.register 'component', -> 'some component'
    app.component

    expect(-> app.before 'component').to.throw /already created/
    expect(-> app.after 'component').to.throw /already created/

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
  it "should raise error if callback defined after scope already started" do
    activateFiber ->
      app.activate 'custom', ->
        expect(-> app.beforeScope 'custom').to.throw /already started/
        expect(-> app.afterScope 'custom').to.throw /already started/