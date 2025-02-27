CocoClass = require 'core/CocoClass'
PlayHeroesModal = require 'views/play/modal/PlayHeroesModal'
InventoryModal = require 'views/play/menu/InventoryModal'
Level = require 'models/Level'
LevelSession = require 'models/LevelSession'
SuperModel = require 'models/SuperModel'
ThangType = require 'models/ThangType'
utils = require 'core/utils'

lastHeroesEarned = me.get('earned')?.heroes ? []
lastHeroesPurchased = me.get('purchased')?.heroes ? []

module.exports = class LevelSetupManager extends CocoClass

  constructor: (@options) ->
    super()
    @supermodel = @options.supermodel ? new SuperModel()
    @session = @options.session
    unless @level = @options.level
      @loadLevel()
    if @session
      console.log 'LevelSetupManager given preloaded session:', @session.cid
      @fillSessionWithDefaults()
    else
      console.log 'LevelSetupManager given no preloaded session.'
      @loadSession()

  loadLevel: ->
    levelURL = "/db/level/#{@options.levelID}"
    @level = new Level().setURL levelURL
    @level = @supermodel.loadModel(@level).model
    if @level.loaded then @onLevelSync() else @listenToOnce @level, 'sync', @onLevelSync

  loadSession: ->
    sessionURL = "/db/level/#{@options.levelID}/session"
    #sessionURL += "?team=#{@team}" if @options.team  # TODO: figure out how to get the teams for multiplayer PVP hero style
    if @options.courseID
      sessionURL += "?course=#{@options.courseID}"
      if @options.courseInstanceID
          sessionURL += "&courseInstance=#{@options.courseInstanceID}"
    @session = new LevelSession().setURL sessionURL
    originalCid = @session.cid
    @session = @supermodel.loadModel(@session).model
    if originalCid is @session.cid
      console.log 'LevelSetupManager made a new Level Session', @session
    else
      console.log 'LevelSetupManager used a Level Session from the SuperModel', @session
    if @session.loaded then @onSessionSync() else @listenToOnce @session, 'sync', @onSessionSync

  onLevelSync: ->
    return if @destroyed
    if @waitingToLoadModals
      @waitingToLoadModals = false
      @loadModals()

  onSessionSync: ->
    return if @destroyed
    @session.url = -> '/db/level.session/' + @id
    @fillSessionWithDefaults()

  fillSessionWithDefaults: ->
    if @options.codeLanguage
      @session.set('codeLanguage', @options.codeLanguage)
    heroConfig = _.merge {}, _.cloneDeep(me.get('heroConfig')), @session.get('heroConfig')
    @session.set('heroConfig', heroConfig)
    if @level.loaded
      @loadModals()
    else
      @waitingToLoadModals = true

  loadModals: ->
    if not @level.usesSessionHeroThangType() or utils.isOzaria
      # Don't need to configure inventory; just skip it
      @onInventoryModalPlayClicked()
      return

    # Build modals and prevent them from disappearing.
    @heroesModal = new PlayHeroesModal({supermodel: @supermodel, session: @session, confirmButtonI18N: 'play.next', level: @level, campaign: @options.campaign, hadEverChosenHero: @options.hadEverChosenHero, courseInstanceID: @options.courseInstanceID })
    @inventoryModal = new InventoryModal({supermodel: @supermodel, session: @session, level: @level})
    @heroesModalDestroy = @heroesModal.destroy
    @inventoryModalDestroy = @inventoryModal.destroy
    @heroesModal.destroy = @inventoryModal.destroy = _.noop
    @listenTo @heroesModal, 'confirm-click', @onHeroesModalConfirmClicked
    @listenToOnce @heroesModal, 'hero-loaded', @onceHeroLoaded
    @listenTo @inventoryModal, 'choose-hero-click', @onChooseHeroClicked
    @listenTo @inventoryModal, 'play-click', @onInventoryModalPlayClicked
    @modalsLoaded = true
    if @waitingToOpen
      @waitingToOpen = false
      @open()

  open: ->
    return @waitingToOpen = true unless @modalsLoaded
    firstModal = if @options.hadEverChosenHero then @inventoryModal else @heroesModal
    if @options.levelID is 'the-gem'
      # show hero picker for the first level (the-gem) in junior to default to blocks-text
      firstModal = @heroesModal
    else if ((not _.isEqual(lastHeroesEarned, me.get('earned')?.heroes ? []) or
        not _.isEqual(lastHeroesPurchased, me.get('purchased')?.heroes ? [])) and
        (utils.isOzaria or not (me.isAnonymous() and me.isInHourOfCode())))
      console.log 'Showing hero picker because heroes earned/purchased has changed.'
      firstModal = @heroesModal
    else if allowedHeroOriginals = @level.get 'allowedHeroes'
      unless (utils.isOzaria and _.contains allowedHeroOriginals, me.get('ozariaUserOptions')?.isometricThangTypeOriginal) or (utils.isCodeCombat and _.contains allowedHeroOriginals, me.get('heroConfig')?.thangType)
        firstModal = @heroesModal

    lastHeroesEarned = me.get('earned')?.heroes ? []
    lastHeroesPurchased = me.get('purchased')?.heroes ? []

    if firstModal is @inventoryModal and @level.get('product', true) is 'codecombat-junior'
      # Skip inventory screen
      return @onInventoryModalPlayClicked()

    @options.parent.openModalView(firstModal)
    @trigger 'open'
    #    @inventoryModal.onShown() # replace?

  #- Modal events

  onceHeroLoaded: (e) ->
     @inventoryModal.setHero(e.hero) if window.currentModal is @inventoryModal

  onHeroesModalConfirmClicked: (e) ->
    skipInventroyModal = false
    if @level.get('product', true) is 'codecombat-junior'
      skipInventroyModal = true
    else if @options.classroom and @options.classroom.get('classroomItems')? and not @options.classroom.get('classroomItems', true)
      skipInventroyModal = true
    if skipInventroyModal
      # Skip inventory screen
      return @onInventoryModalPlayClicked()
    @options.parent.openModalView(@inventoryModal)
    @inventoryModal.render()
    @inventoryModal.didReappear()
    @inventoryModal.onShown()
    @inventoryModal.setHero(e.hero) if e.hero
    window.tracker?.trackEvent 'Choose Inventory', category: 'Play Level'

  onChooseHeroClicked: ->
    @options.parent.openModalView(@heroesModal)
    @heroesModal.render()
    @heroesModal.didReappear()
    @inventoryModal.endHighlight()
    window.tracker?.trackEvent 'Change Hero', category: 'Play Level'

  onInventoryModalPlayClicked: ->
    @navigatingToPlay = true
    PlayLevelView = 'views/play/level/PlayLevelView'
    LadderView = 'views/ladder/LadderView'
    viewClass = if @options.levelPath is 'ladder' then LadderView else PlayLevelView
    route = "/play/#{@options.levelPath || 'level'}/#{@options.levelID}?"
    route += "&codeLanguage=" + @level.get('primerLanguage') if @level.get('primerLanguage')
    if @options.courseID? and @options.courseInstanceID?
      route += "&course=#{@options.courseID}&course-instance=#{@options.courseInstanceID}"
    else if @options.courseID?
      route += "&course=#{@options.courseID}"
    @supermodel.registerModel(@session)
    Backbone.Mediator.publish 'router:navigate', {
      route, viewClass
      viewArgs: [{supermodel: @supermodel, sessionID: @session.id}, @options.levelID]
    }

  destroy: ->
    @heroesModalDestroy?.call @heroesModal unless @heroesModal?.destroyed
    @inventoryModalDestroy?.call @inventoryModal unless @inventoryModal?.destroyed
    super()
