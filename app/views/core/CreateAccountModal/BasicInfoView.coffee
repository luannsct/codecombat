require('app/styles/modal/create-account-modal/basic-info-view.sass')
CocoView = require 'views/core/CocoView'
AuthModal = require 'views/core/AuthModal'
template = require 'app/templates/core/create-account-modal/basic-info-view'
forms = require 'core/forms'
errors = require 'core/errors'
User = require 'models/User'
State = require 'models/State'
store = require 'core/store'
globalVar = require 'core/globalVar'
{capitalizeFirstLetter, isCodeCombat, isOzaria} = require 'core/utils'
_ = require 'lodash'
userUtils = require '../../../lib/user-utils'

###
This view handles the primary form for user details — name, email, password, etc,
and the AJAX that actually creates the user.

It also handles facebook/g+ login, which if used, open one of two other screens:
sso-already-exists: If the facebook/g+ connection is already associated with a user, they're given a log in button
sso-confirm: If this is a new facebook/g+ connection, ask for a username, then allow creation of a user

The sso-confirm view *inherits from this view* in order to share its account-creation logic and events.
This means the selectors used in these events must work in both templates.

This view currently uses the old form API instead of stateful render.
It needs some work to make error UX and rendering better, but is functional.
###

module.exports = class BasicInfoView extends CocoView
  id: 'basic-info-view'
  template: template

  events:
    'change input[name="firstName"]': 'onChangeNames'
    'change input[name="lastName"]': 'onChangeNames'
    'change input[name="email"]': 'onChangeEmail'
    'change input[name="name"]': 'onChangeName'
    'change input[name="password"]': 'onChangePassword'
    'click .back-button': 'onClickBackButton'
    'submit form': 'onSubmitForm'
    'click .use-suggested-name-link': 'onClickUseSuggestedNameLink'
    'click #facebook-signup-btn': 'onClickSsoSignupButton'
    'click #clever-signup-btn': 'onClickSsoSignupButton'

  initialize: ({ @signupState } = {}) ->
    @state = new State {
      suggestedNameText: '...'
      checkEmailState: 'standby' # 'checking', 'exists', 'available'
      checkEmailValue: null
      checkEmailPromise: null
      checkNameState: 'standby' # same
      checkNameValue: null
      checkNamePromise: null
      error: ''
    }
    @listenTo @state, 'change:checkEmailState', -> @renderSelectors('.email-check')
    @listenTo @state, 'change:checkNameState', -> @renderSelectors('.name-check')
    @listenTo @state, 'change:error', -> @renderSelectors('.error-area')
    @listenTo @signupState, 'change:facebookEnabled', -> @renderSelectors('.auth-network-logins')
    @listenTo @signupState, 'change:gplusEnabled', -> @renderSelectors('.auth-network-logins')

    # Prefill form by url params
    url = new URLSearchParams window.location.search

    if url.get 'prefill'
      prefillData = JSON.parse(Buffer.from(url.get('prefill'), 'base64').toString('ascii'))
    else
      prefillData = ['firstName', 'lastName', 'email'].reduce (data = {}, param) =>
        value = url.get param
        if value then data[param] = url.get param
        data
      , {}

    Object.entries(prefillData).forEach ([param,value]) =>
      @signupState.get('signupForm')[param]= value

    @hideEmail = if isCodeCombat then userUtils.shouldHideEmail() else false
    @showLibraryIdInsteadOfUsername = if isCodeCombat then userUtils.shouldShowLibraryLoginModal() else false

  afterRender: ->
    @$el.find('#first-name-input').focus()
    application.gplusHandler.loadAPI({
      success: =>
        @handleSSOConnect(application.gplusHandler, 'gplus')
    })
    super()

  # These values are passed along to AuthModal if the user clicks "Sign In" (handled by CreateAccountModal)
  updateAuthModalInitialValues: (values) ->
    @signupState.set {
      authModalInitialValues: _.merge @signupState.get('authModalInitialValues'), values
    }, { silent: true }

  onChangeEmail: (e) ->
    @updateAuthModalInitialValues { email: @$(e.currentTarget).val() }
    @checkEmail()

  checkEmail: ->
    email = @$('[name="email"]').val()

    if @hideEmail
      return Promise.resolve(true)

    if @signupState.get('path') isnt 'student' and (not _.isEmpty(email) and email is @state.get('checkEmailValue'))
      return @state.get('checkEmailPromise')

    if not (email and forms.validateEmail(email))
      @state.set({
        checkEmailState: 'standby'
        checkEmailValue: email
        checkEmailPromise: null
      })
      return Promise.resolve()

    @state.set({
      checkEmailState: 'checking'
      checkEmailValue: email

      checkEmailPromise: (User.checkEmailExists(email)
      .then ({exists}) =>
        return unless email is @$('[name="email"]').val()
        if exists
          @state.set('checkEmailState', 'exists')
        else
          @state.set('checkEmailState', 'available')
      .catch (e) =>
        @state.set('checkEmailState', 'standby')
        throw e
      )
    })
    return @state.get('checkEmailPromise')

  onChangeNames: () ->
    firstName = @$el.find('#first-name-input').val() or ''
    lastName = @$el.find('#last-name-input').val() or ''
    userName = capitalizeFirstLetter(firstName)+capitalizeFirstLetter(lastName)
    @$el.find('#username-input').val(userName)
    @checkName()

  onChangeName: (e) ->
    @updateAuthModalInitialValues { name: @$(e.currentTarget).val() }

    # Go through the form library so this follows the same trimming rules
    name = forms.formToObject(@$el.find('#basic-info-form')).name
    # Carefully remove the error for just this field
    @$el.find('[for="username-input"] ~ .help-block.error-help-block').remove()
    @$el.find('[for="username-input"]').closest('.form-group').removeClass('has-error')
    if name and forms.validateEmail(name)
      forms.setErrorToProperty(@$el, 'name', $.i18n.t('signup.name_is_email'))
      return

    @checkName()

  checkName: ->
    return Promise.resolve() if @signupState.get('path') is 'teacher'

    name = @$('input[name="name"]').val()

    if name is @state.get('checkNameValue')
      return @state.get('checkNamePromise')

    if not name
      @state.set({
        checkNameState: 'standby'
        checkNameValue: name
        checkNamePromise: null
      })
      return Promise.resolve()

    @state.set({
      checkNameState: 'checking'
      checkNameValue: name

      checkNamePromise: (User.checkNameConflicts(name)
      .then ({ suggestedName, conflicts }) =>
        return unless name is @$('input[name="name"]').val()
        if conflicts
          suggestedNameText = $.i18n.t('signup.name_taken').replace('{{suggestedName}}', suggestedName)
          @state.set({ checkNameState: 'exists', suggestedNameText })
        else
          @state.set { checkNameState: 'available' }
      .catch (error) =>
        @state.set('checkNameState', 'standby')
        throw error
      )
    })

    return @state.get('checkNamePromise')

  onChangePassword: (e) ->
    @updateAuthModalInitialValues { password: @$(e.currentTarget).val() }

  checkBasicInfo: (data) ->
    forms.clearFormAlerts(@$el)

    if data.name and forms.validateEmail(data.name)
      forms.setErrorToProperty(@$el, 'name', $.i18n.t('signup.name_is_email'))
      return false

    res = tv4.validateMultiple data, @formSchema()
    if res.errors and res.errors.some((err) -> err.dataPath == '/password')
      res.errors = res.errors.filter((err) -> err.dataPath != '/password')
      res.errors.push({
        dataPath: '/password',
        message: $.i18n.t('signup.invalid')
      })

    forms.applyErrorsToForm(@$('form'), res.errors) unless res.valid
    return res.valid

  formSchema: ->
    if isOzaria
      type: 'object'
      properties:
        email: User.schema.properties.email
        name: User.schema.properties.name
        password: User.schema.properties.password
      required: switch @signupState.get('path')
        when 'student' then ['name', 'password', 'firstName', 'lastName']
        when 'teacher' then ['password', 'email', 'firstName', 'lastName']
        else ['name', 'password', 'email']
    else
      type: 'object'
      properties:
        email: User.schema.properties.email
        name: User.schema.properties.name
        password: User.schema.properties.password
        firstName: User.schema.properties.firstName
        lastName: User.schema.properties.lastName
      required: switch @signupState.get('path')
        when 'student' then ['name', 'password', 'firstName'].concat(if me.showChinaRegistration() then [] else ['lastName'])
        when 'teacher' then ['password', 'email', 'firstName'].concat(if me.showChinaRegistration() then [] else ['lastName'])
        else
          ['name', 'password'].concat(if @hideEmail then [] else ['email'])

  onClickBackButton: ->
    if @signupState.get('path') is 'teacher'
      window.tracker?.trackEvent 'CreateAccountModal Teacher BasicInfoView Back Clicked', category: 'Teachers'
    if @signupState.get('path') is 'student'
      window.tracker?.trackEvent 'CreateAccountModal Student BasicInfoView Back Clicked', category: 'Students'
    if @signupState.get('path') is 'individual'
      window.tracker?.trackEvent 'CreateAccountModal Individual BasicInfoView Back Clicked', category: 'Individuals'
    @trigger 'nav-back'

  onClickUseSuggestedNameLink: (e) ->
    @$('input[name="name"]').val(@state.get('suggestedName'))
    forms.clearFormAlerts(@$el.find('input[name="name"]').closest('.form-group').parent())

  onSubmitForm: (e) ->
    if @signupState.get('path') is 'teacher'
      window.tracker?.trackEvent 'CreateAccountModal Teacher BasicInfoView Submit Clicked', category: 'Teachers'
    if @signupState.get('path') is 'student'
      window.tracker?.trackEvent 'CreateAccountModal Student BasicInfoView Submit Clicked', category: 'Students'
    if @signupState.get('path') is 'individual'
      window.tracker?.trackEvent 'CreateAccountModal Individual BasicInfoView Submit Clicked', category: 'Individuals'
    @state.unset('error')
    e.preventDefault()
    data = forms.formToObject(e.currentTarget)
    valid = @checkBasicInfo(data)
    return unless valid

    @displayFormSubmitting()
    AbortError = new Error()

    @checkEmail()
    .then @checkName()
    .then =>
      if not (@state.get('checkEmailState') in ['available', 'standby'] and (@state.get('checkNameState') is 'available' or @signupState.get('path') is 'teacher'))
        throw AbortError

      # update User
      emails = _.assign({}, me.get('emails'))
      emails.generalNews ?= {}
      if me.inEU()
        emails.generalNews.enabled = false
        me.set('unsubscribedFromMarketingEmails', true)
      else
        emails.generalNews.enabled = not _.isEmpty(@state.get('checkEmailValue'))
      me.set('emails', emails)
      me.set(_.pick(data, 'firstName', 'lastName'))

      unless _.isNaN(@signupState.get('birthday').getTime())
        me.set('birthday', @signupState.get('birthday').toISOString().slice(0,7))

      me.set(_.omit(@signupState.get('ssoAttrs') or {}, 'email', 'facebookID', 'gplusID'))

      jqxhr = me.save()
      if not jqxhr
        console.error(me.validationError)
        throw new Error('Could not save user')

      return new Promise(jqxhr.then)

    .then (newUser) =>
      # More data will be added by the server so make sure to trigger an identify call after page reload
      globalVar.application.tracker.identifyAfterNextPageLoad()

      # Don't sign up, kick to TeacherComponent instead
      if @signupState.get('path') is 'teacher'
        @signupState.set({
          signupForm: _.pick(forms.formToObject(@$el), 'firstName', 'lastName', 'email', 'password', 'subscribe')
        })
        @trigger 'signup'
        return

      # Use signup method
      unless User.isSmokeTestUser({ email: @signupState.get('signupForm').email })
        # Set new user data and call initial identify
        store.dispatch('me/authenticated', newUser)
        globalVar.application.tracker.identify()

      switch @signupState.get('ssoUsed')
        when 'gplus'
          { email, gplusID } = @signupState.get('ssoAttrs')
          { name } = forms.formToObject(@$el)
          jqxhr = me.signupWithGPlus(name, email, gplusID)
        when 'facebook'
          { email, facebookID } = @signupState.get('ssoAttrs')
          { name } = forms.formToObject(@$el)
          jqxhr = me.signupWithFacebook(name, email, facebookID)
        else
          { name, email, password } = forms.formToObject(@$el)
          jqxhr = me.signupWithPassword(name, email, password)

      return new Promise(jqxhr.then)

    .then =>
      trackerCalls = []

      loginMethod = 'CodeCombat'
      if @signupState.get('ssoUsed') is'gplus'
        loginMethod = 'GPlus'
        trackerCalls.push(
          window.tracker?.trackEvent 'Google Login', category: "Signup", label: 'GPlus'
        )
      else if @signupState.get('ssoUsed') is 'facebook'
        loginMethod = 'Facebook'
        trackerCalls.push(
          window.tracker?.trackEvent 'Facebook Login', category: "Signup", label: 'Facebook'
        )

      return Promise.all(trackerCalls).catch(->)

    .then =>
      { classCode, classroom } = @signupState.attributes
      if classCode and classroom
        return new Promise(classroom.joinWithCode(classCode).then)

    .then =>
      @finishSignup()

    .catch (e) =>
      @displayFormStandingBy()
      if e is AbortError
        return
      else
        console.error 'BasicInfoView form submission Promise error:', e
        if e.responseJSON?.i18n
          @state.set('error', $.i18n.t(e.responseJSON?.i18n) or 'Unknown Error')
        else
          @state.set('error', e.responseJSON?.message or 'Unknown Error')

  finishSignup: ->
    if @signupState.get('path') is 'teacher'
      window.tracker?.trackEvent 'CreateAccountModal Teacher BasicInfoView Submit Success', category: 'Teachers'
    if @signupState.get('path') is 'student'
      window.tracker?.trackEvent 'CreateAccountModal Student BasicInfoView Submit Success', category: 'Students'
    if @signupState.get('path') is 'individual'
      window.tracker?.trackEvent 'CreateAccountModal Individual BasicInfoView Submit Success', category: 'Individuals', wantInSchool: @$('#want-in-school-checkbox').is(':checked')
      if @$('#want-in-school-checkbox').is(':checked')
        @signupState.set 'wantInSchool', true
    @trigger 'signup'

  displayFormSubmitting: ->
    @$('#create-account-btn').text($.i18n.t('signup.creating')).attr('disabled', true)
    @$('input').attr('disabled', true)

  displayFormStandingBy: ->
    @$('#create-account-btn').text($.i18n.t('login.sign_up')).attr('disabled', false)
    @$('input').attr('disabled', false)

  onClickSsoSignupButton: (e) ->
    e.preventDefault()
    ssoUsed = $(e.currentTarget).data('sso-used')
    if isOzaria
      handler = if ssoUsed is 'facebook' then application.facebookHandler else application.gplusHandler
    else
      handler = switch ssoUsed
        when 'facebook' then application.facebookHandler
        when 'gplus' then application.gplusHandler
        when 'clever' then 'clever'

    if handler is 'clever'
      if window.location.hostname in ['next.codecombat.com', 'localhost']  # dev
        cleverClientId = '943ece596555cac13fcc'
        redirectTo = 'https://next.codecombat.com/auth/login-clever'
        districtId = '5b2ad81a709e300001e2cd7a'  # Clever Library test district
      else  # prod
        cleverClientId = 'ffce544a7e02c0daabf2'
        redirectTo = 'https://codecombat.com/auth/login-clever'
      url = "https://clever.com/oauth/authorize?response_type=code&redirect_uri=#{encodeURIComponent(redirectTo)}&client_id=#{cleverClientId}"
      if districtId
        url += '&district_id=' + districtId
      window.open url, '_blank'
      return

    @handleSSOConnect(handler, ssoUsed)

  handleSSOConnect: (handler, ssoUsed) ->
    handler.connect({
      context: @
      success: (resp = {}) ->
        handler.loadPerson({
          resp: resp
          context: @
          success: (ssoAttrs) ->
            @signupState.set { ssoAttrs }
            { email } = ssoAttrs
            User.checkEmailExists(email).then ({exists}) =>
              @signupState.set {
                ssoUsed
                email: ssoAttrs.email
              }
              if exists
                @trigger 'sso-connect:already-in-use'
              else
                @trigger 'sso-connect:new-user'
        })
    })
