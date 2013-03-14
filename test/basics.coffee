require './helper'

describe "Instance scope", ->
  it "should register and get component", ->
    app.register 'component', scope: 'instance', -> ['some component']
    expect(app.component).to.eql ['some component']
    expect(app.component).to.not.equal app.component

describe "Static scope", ->
  it "should register and get component", ->
    app.register 'component', -> ['some component']
    expect(app.component).to.eql ['some component']
    expect(app.component).to.equal app.component

  it "should set component", ->
    component = "some component"
    app.register 'component', -> 'some component'
    expect(app.component).to.eql 'some component'
    app.component = 'another component'
    expect(app.component).to.eql 'another component'

describe "Custom scope", ->
  it "should activate scope", ->
    expect(app.isActive('custom')).to.eql false
    activateFiber ->
      app.activate 'custom', ->
        expect(app.isActive('custom')).to.eql true
    expect(app.isActive('custom')).to.eql false

  it "should register and get component", ->
    app.register 'component', scope: 'custom', -> 'some component'
    activateFiber ->
      app.activate 'custom', ->
        expect(app.component).to.eql 'some component'

  it "should set component", ->
    app.register 'component', scope: 'custom', -> 'some component'
    activateFiber ->
      app.activate 'custom', ->
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

    expect(events).to.eql ['before', 'after']

describe "Scope callbacks", ->
  it "should fire before and after callbacks", ->
    events = []
    app.beforeScope 'custom', -> events.push 'before'
    app.afterScope 'custom', -> events.push 'after'
    activateFiber ->
      app.activate 'custom', ->
    expect(events).to.eql ['before', 'after']