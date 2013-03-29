require './helper'

describe "Dependency Injector", ->
  it "should allow to express dependencies explicitly", ->
    events = []
    app.register 'a', ->
      events.push 'a'
      'a'
    app.register 'b', dependencies: ['a'], ->
      events.push 'b'
      'b'
    app.b
    expect(events).to.eql ['a', 'b']

describe "Application scope", ->
  it "should register and get component", ->
    app.register 'component', -> {name: 'some component'}
    expect(app.component).to.have.property('name').to.eql 'some component'
    expect(app.component).to.equal app.component

  it "should set component", ->
    component = "some component"
    app.register 'component', -> 'some component'
    expect(app.component).to.eql 'some component'
    app.component = 'another component'
    expect(app.component).to.eql 'another component'

describe "Global scope", ->
  it "should register and get component", ->
    app.register 'component', scope: 'global', -> {name: 'some component'}
    expect(app.component).to.have.property('name').to.eql 'some component'
    expect(app.component).to.equal app.component

  it "should set component", ->
    component = "some component"
    app.register 'component', scope: 'global', -> 'some component'
    expect(app.component).to.eql 'some component'
    app.component = 'another component'
    expect(app.component).to.eql 'another component'

describe "Fiber scope", ->
  it "should activate scope", ->
    expect(app.hasScope('fiber')).to.eql false
    sync.fiber ->
      expect(app.hasScope('fiber')).to.eql true
    expect(app.hasScope('fiber')).to.eql false

  it "should register and get component", ->
    app.register 'component', scope: 'fiber', -> {name: 'some component'}
    sync.fiber ->
      expect(app.component).to.have.property('name').to.eql 'some component'

  it "should set component", ->
    app.register 'component', scope: 'fiber', -> 'some component'
    sync.fiber ->
      expect(app.component).to.eql 'some component'
      app.component = 'another component'
      expect(app.component).to.eql 'another component'

describe "Instance scope", ->
  it "should register and get component", ->
    app.register 'component', scope: 'instance', -> {name: 'some component'}
    expect(app.component).to.have.property('name').to.eql 'some component'
    expect(app.component).to.not.equal app.component

describe "Custom scope", ->
  it "should activate scope", ->
    expect(app.hasScope('custom')).to.eql false
    sync.fiber ->
      app.scope 'custom', ->
        expect(app.hasScope('custom')).to.eql true
    expect(app.hasScope('custom')).to.eql false

  it "should register and get component", ->
    app.register 'component', scope: 'custom', -> {name: 'some component'}
    sync.fiber ->
      app.scope 'custom', ->
        expect(app.component).to.have.property('name').to.eql 'some component'

  it "should set component", ->
    app.register 'component', scope: 'custom', -> 'some component'
    sync.fiber ->
      app.scope 'custom', ->
        expect(app.component).to.eql 'some component'
        app.component = 'another component'
        expect(app.component).to.eql 'another component'

describe "Component callbacks", ->
  it "should fire before and after callbacks", ->
    app.register 'component', -> 'some component'

    events = []
    app.before 'component', -> events.push 'before'

    app.after 'component', ->
      expect(app.component).to.eql 'some component'
      events.push 'after'

    app.component
    expect(events).to.eql ['before', 'after']

describe "Scope callbacks", ->
  it "should fire before and after callbacks", ->
    events = []
    app.beforeScope 'custom', -> events.push 'before'
    app.afterScope 'custom', -> events.push 'after'
    sync.fiber ->
      app.scope 'custom', ->
    expect(events).to.eql ['before', 'after']