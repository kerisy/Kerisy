/*
 * Kerisy - A high-level D Programming Language Web framework that encourages rapid development and clean, pragmatic design.
 *
 * Copyright (C) 2021, Kerisy.com
 *
 * Website: https://www.kerisy.com
 *
 * Licensed under the Apache-2.0 License.
 *
 */

module kerisy.controller.Controller;

import kerisy.application.Application;
import kerisy.auth;
import kerisy.breadcrumb.BreadcrumbsManager;
import kerisy.controller.RestController;
import kerisy.middleware.AuthMiddleware;
import kerisy.middleware.Middleware;
import kerisy.middleware.MiddlewareInfo;
import kerisy.middleware.MiddlewareInterface;

import kerisy.http.Request;
import kerisy.http.Form;
import kerisy.i18n.I18n;
import kerisy.provider;
import kerisy.BasicSimplify;
import kerisy.view;

public import kerisy.http.Response;
public import hunt.http.server;
public import hunt.http.routing;
import hunt.http.HttpConnection;

import hunt.cache;
// import hunt.entity.EntityManagerFactory;
import hunt.logging.ConsoleLogger;
import hunt.redis.Redis;
import hunt.redis.RedisPool;
import hunt.validation;

import poodinis;

import core.memory;
import core.thread;

import std.algorithm;
import std.exception;
import std.string;
import std.traits;
import std.variant;

struct Action {
}

private enum string TempVarName = "__var";
// private enum string IndentString = "\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t\t";  // 16 tabs
private enum string IndentString = "                                ";  // 32 spaces

string indent(size_t number) {
    assert(number>0 && IndentString.length, "Out of range");
    return IndentString[0..number];
}

class ControllerBase(T) : Controller {
    // mixin MakeController;
    mixin HuntDynamicCallFun!(T, moduleName!T);
}

/**
 * 
 */
abstract class Controller
{
    private Request _request;
    private Response _response;

    private MiddlewareInfo[] _allowedMiddlewares;
    private MiddlewareInfo[] _skippedMiddlewares;

    protected
    {
        RoutingContext _routingContext;
        View _view;
        ///called before all actions
        MiddlewareInterface[string] middlewares;
    }

    this() {
    }

    RoutingContext routingContext() {
        if(_routingContext is null) {
            throw new Exception("Can't call this method in the constructor.");
        }
        return _routingContext;
    }

    Request request() {
        return CreateRequest(false);
    }

    protected Request CreateRequest(bool isRestful = false) {
        if(_request is null) {
            RoutingContext context = routingContext();

            Variant itemAtt = context.getAttribute(RouterContex.stringof);
            RouterContex routeContex;
            if(itemAtt.hasValue()) {
                routeContex = cast(RouterContex)itemAtt.get!(Object);
            }

            HttpConnection httpConnection = context.httpConnection();

            _request = new Request(context.getRequest(), 
                                    httpConnection.getRemoteAddress(),
                                    routeContex);

            _request.isRestful = isRestful;
        }
        return _request;
    }

    final @property Response response() {
        if(_response is null) {
            _response = new Response(routingContext().getResponse());
        }
        return _response;
    }

    // reset to a new response
    @property void response(Response r) {
        assert(r !is null, "The response can't be null");
        _response = r;
        routingContext().response = r.httpResponse;
    }

    /**
     * Handle the auth status
     */
    Auth auth() {
        return this.request().auth();
    }

    /**
     * Get the currently authenticated user.
     */
    Identity User() {
        return this.request().auth().user();
    }

    @property View view()
    {
        if (_view is null)
        {
            Request req = this.request();
            _view = serviceContainer.resolve!View();
            _view.SetRouteGroup(routingContext().groupName());
            _view.SetLocale(req.Locale());
            _view.env().request = req;
            
            // _view.Assign("input", req.input());
        }

        return _view;
    }

    private RouteConfigManager RouteManager() {
        return serviceContainer.resolve!(RouteConfigManager);
    }


    /// called before action  return true is continue false is finish
    bool Before()
    {
        return true;
    }

    /// called after action  return true is continue false is finish
    bool After()
    {
        return true;
    }

    ///add middleware
    ///return true is ok, the named middleware is already exist return false
    bool AddMiddleware(MiddlewareInterface m)
    {
        if(m is null || this.middlewares.get(m.name(), null) !is null)
        {
            return false;
        }

        this.middlewares[m.name()]= m;
        return true;
    }

    /**
     * 
     */
    void AddAcceptedMiddleware(string fullName, string actionName, string controllerName, string moduleName) {
        MiddlewareInfo info = new MiddlewareInfo(fullName, actionName, controllerName, moduleName);
        _allowedMiddlewares ~= info;
    }
    
    /**
     * 
     */
    void AddSkippedMiddleware(string fullName, string actionName, string controllerName, string moduleName) {
        MiddlewareInfo info = new MiddlewareInfo(fullName, actionName, controllerName, moduleName);
        _skippedMiddlewares ~= info;
    }

    // All the middlewares defined in the route group
    protected MiddlewareInterface[] GetAcceptedMiddlewaresInRouteGroup(string routeGroup) {
        MiddlewareInterface[] result;

        TypeInfo_Class[] routeMiddlewares;
        routeMiddlewares = RouteManager().Group(routeGroup).AllowedMiddlewares();
        foreach(TypeInfo_Class info; routeMiddlewares) {
            version(HUNT_AUTH_DEBUG) tracef("routeGroup: %s, fullName: %s", routeGroup, info.name);

            MiddlewareInterface middleware = cast(MiddlewareInterface)info.create();
            if(middleware is null) {
                warningf("%s is not a MiddlewareInterface", info.name);
            } else {              
                result ~= middleware;
            }
        }

        return result;
    }

    // All the middlewares defined in the route item
    protected MiddlewareInterface[] GetAcceptedMiddlewaresInRouteItem(string routeGroup, string actionId) {
        MiddlewareInterface[] result;
        TypeInfo_Class[] routeMiddlewares;

        RouteItem routeItem = RouteManager().Get(routeGroup, actionId);
            if(routeItem !is null) {
            routeMiddlewares = routeItem.AllowedMiddlewares();
            foreach(TypeInfo_Class info; routeMiddlewares) {
                warningf("actionId: %s, fullName: %s", actionId, info.name);

                MiddlewareInterface middleware = cast(MiddlewareInterface)info.create();
                if(middleware is null) {
                    warningf("%s is not a MiddlewareInterface", info.name);
                } else {
                    result ~= middleware;
                }
            } 
        }

        return result;
    }

    // All the middlewares defined this Controller's action
    protected MiddlewareInterface[] GetAcceptedMiddlewaresInController(string actionName) {
        MiddlewareInterface[] result;

        auto middlewares = _allowedMiddlewares.filter!( m => m.action == actionName);
        // auto middlewares = _allowedMiddlewares.filter!( (m) { 
        //     trace(m.action, " == ", name);
        //     return m.action == name;
        // });

        foreach(MiddlewareInfo info; middlewares) {
            // warningf("fullName: %s, action: %s", info.fullName, info.action);

            MiddlewareInterface middleware = cast(MiddlewareInterface)Object.factory(info.fullName);
            if(middleware is null) {
                warningf("%s is not a MiddlewareInterface", info.fullName);
            } else {             
                result ~= middleware;
            }
        }

        return result;
    }

    // All the middlewares defined in the route group
    protected bool IsSkippedMiddlewareInRouteGroup(string fullName, string routeGroup) {
        TypeInfo_Class[] routeMiddlewares = RouteManager().Group(routeGroup).SkippedMiddlewares();
        foreach(TypeInfo_Class typeInfo; routeMiddlewares) {
            if(typeInfo.name == fullName) return true;
        }

        return false;
    }
    
    // All the middlewares defined in the route item
    protected bool IsSkippedMiddlewareInRouteItem(string fullName, string routeGroup, string actionId) {
        RouteItem routeItem = RouteManager().GetRoute(routeGroup, actionId);
        if(routeItem !is null) {
            TypeInfo_Class[] routeMiddlewares = routeItem.SkippedMiddlewares();
            foreach(TypeInfo_Class typeInfo; routeMiddlewares) {
                if(typeInfo.name == fullName) return true;
            }
        }

        return false;
    }

    // All the middlewares defined this Controller's action
    protected bool IsSkippedMiddlewareInControllerAction(string actionName, string middlewareName) {
        bool r = _skippedMiddlewares.canFind!(m => m.fullName == middlewareName && m.action == actionName);
        return r;
    }

    // get all middleware
    MiddlewareInterface[string] GetMiddlewares()
    {
        return this.middlewares;
    }

    protected final Response HandleMiddlewares(string actionName) {
        Request req = this.request();
        string actionId = req.actionId();
        string routeGroup = req.routeGroup();
        
        version (HUNT_DEBUG) {
            infof("middlware: routeGroup=%s, path=%s, method=%s, actionId=%s, actionName=%s", 
               routeGroup, req.Path(),  req.Method, actionId, actionName);
        }

        /////////////
        // Checking all the allowed middlewares.
        /////////////

        // Allowed middlewares in Controller's Action
        MiddlewareInterface[] allowedMiddlewares = GetAcceptedMiddlewaresInController(actionName);
        
        // Allowed middlewares in RouteItem
        allowedMiddlewares ~= GetAcceptedMiddlewaresInRouteItem(routeGroup, actionId);

        foreach(MiddlewareInterface m; allowedMiddlewares) {
            string name = m.name();
            version (HUNT_DEBUG) logDebugf("The %s is processing ...", name);

            auto response = m.OnProcess(req, this.response);
            if (response is null) {
                continue;
            }

            version (HUNT_DEBUG) infof("The access is blocked by %s.", name);
            return response;
        }
        
        // Allowed middlewares in RouteGroup
        allowedMiddlewares = GetAcceptedMiddlewaresInRouteGroup(routeGroup);
        foreach(MiddlewareInterface m; allowedMiddlewares) {
            string name = m.name();
            version (HUNT_DEBUG) logDebugf("The %s is processing ...", name);

            if(IsSkippedMiddlewareInControllerAction(actionName, name)) {
                version (HUNT_DEBUG) infof("A middleware [%s] is skipped ...", name);
                return null;
            }

            if(IsSkippedMiddlewareInRouteItem(name, routeGroup, actionId)) {
                version (HUNT_DEBUG) infof("A middleware [%s] is skipped ...", name);
                return null;
            }

            auto response = m.OnProcess(req, this.response);
            if (response is null) {
                continue;
            }

            version (HUNT_DEBUG) infof("The access is blocked by %s.", m.name);
            return response;
        }

        /////////////
        // Checking all the directly registed middlewares in Controller.
        /////////////

        foreach (m; middlewares) {
            string name = m.name();
            version (HUNT_DEBUG) logDebugf("The %s is processing ...", name);
            if(IsSkippedMiddlewareInControllerAction(actionName, name)) {
                version (HUNT_DEBUG) infof("A middleware [%s] is skipped ...", name);
                return null;
            }

            if(IsSkippedMiddlewareInRouteItem(name, routeGroup, actionId)) {
                version (HUNT_DEBUG) infof("A middleware [%s] is skipped ...", name);
                return null;
            }

            auto response = m.OnProcess(req, this.response);
            if (response is null) {
                continue;
            }

            version (HUNT_DEBUG) logDebugf("The access is blocked by %s.", name);
            return response;
        }

        return null;
    }

    string ProcessGetNumericString(string value)
    {
        import std.string;

        if (!isNumeric(value))
        {
            return "0";
        }

        return value;
    }

    Response ProcessResponse(Response res)
    {
        // TODO: Tasks pending completion -@zhangxueping at 2020-01-06T14:01:43+08:00
        // 
        // have ResponseHandler binding?
        // if (res.httpResponse() is null)
        // {
        //     res.setHttpResponse(request.responseHandler());
        // }

        return res;
    }

    ConstraintValidatorContext validate() {
        if(_context is null) {
            // assert(!_currentActionName.empty(), "No currentActionName found!");
            _context = new DefaultConstraintValidatorContext();

            auto itemPtr = _currentActionName in _actionValidators;
            // assert(itemPtr !is null, format("No handler found for action: %s!", _currentActionName));
            if(itemPtr is null) {
                warning(format("No validator found for action: %s.", _currentActionName));
            } else {
                try {
                    (*itemPtr)(_context);  
                } catch(Exception ex) {
                    warning(ex.msg);
                    version(HUNT_DEBUG) warning(ex);
                }
            }          
        }

        return _context;
    }
    private ConstraintValidatorContext _context;
    protected string _currentActionName;
    protected QueryParameterValidator[string] _actionValidators;

    protected void raiseError(Response response) {
        this.response = onError(response);
    }

    protected Response onError(Response response) {
        return response;
    }

    protected void Done() {
        Request req = request();
        
        Response resp = response();
        HttpSession session = req.Session(false);
        if (session !is null ) // && session.isNewSession()
        {
            resp.WithCookie(new Cookie(DefaultSessionIdName, session.getId(), session.getMaxInactiveInterval(), 
                    "/", null, false, false));
// TODO: Tasks pending completion -@zhangxueping at 2021-04-15T15:58:11+08:00
// 
            // session.reflash();
            session.save();
        }
        req.Flush(); // assure the sessiondata flushed;

        resp.Header("Date", date("Y-m-d H:i:s"));
        resp.Header(HttpHeader.X_POWERED_BY, KERISY_X_POWERED_BY);
        resp.Header(HttpHeader.SERVER, KERISY_FRAMEWORK_SERVER);

        if(!resp.getFields().contains(HttpHeader.CONTENT_TYPE)) {
            resp.Header(HttpHeader.CONTENT_TYPE, MimeType.TEXT_HTML_VALUE);
        }

        HandleCors();
        HandleAuthResponse();
    }

    protected void HandleCors() {
        /**
        CORS support
        http://www.cnblogs.com/feihong84/p/5678895.html
        https://stackoverflow.com/questions/10093053/add-header-in-ajax-request-with-jquery
        */
        ApplicationConfig.HttpConf httpConf = config().http;
        if(httpConf.enableCors) {
            response.setHeader("Access-Control-Allow-Origin", httpConf.allowOrigin);
            response.setHeader("Access-Control-Allow-Methods", httpConf.allowMethods);
            response.setHeader("Access-Control-Allow-Headers", httpConf.allowHeaders);
        }        
    }

    protected void HandleAuthResponse() {
        Request req = request();
        Auth auth = req.auth();

        version(HUNT_AUTH_DEBUG) {
            tracef("Path: %s, isAuthEnabled: %s", 
                req.path,  auth.isEnabled());
        }

        if(!auth.isEnabled()) 
            return;

        AuthenticationScheme authScheme = auth.Scheme();
        string TokenCookieName = auth.TokenCookieName;
        version(HUNT_AUTH_DEBUG) {
            warningf("TokenCookieName: %s, authScheme: %s, isAuthenticated: %s, isLogout: %s", 
                TokenCookieName, authScheme, auth.user().isAuthenticated, auth.IsLogout());
        }

        Cookie tokenCookie;

        if(auth.CanRememberMe() || auth.IsTokenRefreshed()) {
            ApplicationConfig appConfig = app().Config();
            int tokenExpiration = appConfig.auth.tokenExpiration;

            if(authScheme != AuthenticationScheme.None) {
                string authToken = auth.Token();
                tokenCookie = new Cookie(TokenCookieName, authToken, tokenExpiration);
                auth.TouchSession();
            } 

        } else if(auth.IsLogout()) {
            if(authScheme != AuthenticationScheme.None) {
                tokenCookie = new Cookie(TokenCookieName, "", 0);
            }
        } else if(authScheme != AuthenticationScheme.None) {
            ApplicationConfig appConfig = app().Config();
            int tokenExpiration = appConfig.auth.tokenExpiration;
            string authToken = auth.Token();
            if(authToken.empty()) {
                version(HUNT_AUTH_DEBUG) warning("The auth token is empty!");
            } else {
                tokenCookie = new Cookie(TokenCookieName, authToken, tokenExpiration);
                auth.TouchSession();
            }
        }

        if(tokenCookie !is null) {
            response().WithCookie(tokenCookie);
        }
    }

    void dispose() {
        version(HUNT_HTTP_DEBUG) trace("Do nothing");
    }
}

mixin template MakeController(string moduleName = __MODULE__)
{
    mixin HuntDynamicCallFun!(typeof(this), moduleName);
}

mixin template HuntDynamicCallFun(T, string moduleName) // if(is(T : Controller))
{
public:

    // Middleware
    // pragma(msg, HandleMiddlewareAnnotation!(T, moduleName));

    mixin(HandleMiddlewareAnnotation!(T, moduleName));

    // Actions
    // enum allActions = __createCallActionMethod!(T, moduleName);
    // version (HUNT_DEBUG) 
    // pragma(msg, __createCallActionMethod!(T, moduleName));

    mixin(__createCallActionMethod!(T, moduleName));
    
    shared static this()
    {
        enum routemap = __createRouteMap!(T, moduleName);
        // pragma(msg, routemap);
        mixin(routemap);
    }
}

private
{
    // Predefined characteristic name for a default Action method.
    enum actionName = "Action";
    enum actionNameLength = actionName.length;

    bool IsActionMember(string name)
    {
        return name.length > actionNameLength && name[$ - actionNameLength .. $] == actionName;
    }
}


/// 
string HandleMiddlewareAnnotation(T, string moduleName)() {
    import std.traits;
    import std.format;
    import std.string;
    import std.conv;
    import kerisy.middleware.MiddlewareInterface;

    string str = `
    void initializeMiddlewares() {
    `;
    
    foreach (memberName; __traits(allMembers, T)) {
        alias currentMember = __traits(getMember, T, memberName);
        enum _isActionMember = IsActionMember(memberName);

        static if(isFunction!(currentMember)) {

            static if (hasUDA!(currentMember, Action) || _isActionMember) {
                static if(hasUDA!(currentMember, Middleware)) {
                    enum middlewareUDAs = getUDAs!(currentMember, Middleware);

                    foreach(uda; middlewareUDAs) {
                        foreach(middlewareName; uda.names) {
                            str ~= indent(4) ~ generateAcceptedMiddleware(middlewareName, memberName, T.stringof, moduleName);
                            // str ~= indent(4) ~ format(`this.AddAcceptedMiddleware("%s", "%s", "%s", "%s");`, 
                            //     middlewareName, memberName, T.stringof, moduleName) ~ "\n";
                        }
                    }
                } 
                
                static if(hasUDA!(currentMember, WithoutMiddleware)) {
                    enum skippedMiddlewareUDAs = getUDAs!(currentMember, WithoutMiddleware);
                    foreach(uda; skippedMiddlewareUDAs) {
                        foreach(middlewareName; uda.names) {
                            str ~= indent(4) ~ generateAddSkippedMiddleware(middlewareName, memberName, T.stringof, moduleName);
                            // str ~= indent(4) ~ format(`this.AddSkippedMiddleware("%s", "%s", "%s", "%s");`, 
                            //     middlewareName, memberName, T.stringof, moduleName) ~ "\n";
                        }
                    }
                }
            }
        }
    }
    
    str ~= `
    }    
    `;

    return str;
}

private string generateAcceptedMiddleware(string name, string actionName, string controllerName, string moduleName) {
    string str;

    str = `
        try {
            TypeInfo_Class typeInfo = MiddlewareInterface.Get("%s");
            string fullName = typeInfo.name;
            this.AddAcceptedMiddleware(fullName, "%s", "%s", "%s");
        } catch(Exception ex) {
            warning(ex.msg);
        }
    `;

    str = format(str, name, actionName, controllerName, moduleName);
    return str;
}

private string generateAddSkippedMiddleware(string name, string actionName, string controllerName, string moduleName) {
    string str;

    str = `
        try {
            TypeInfo_Class typeInfo = MiddlewareInterface.Get("%s");
            string fullName = typeInfo.name;
            this.AddSkippedMiddleware(fullName, "%s", "%s", "%s");
        } catch(Exception ex) {
            warning(ex.msg);
        }
    `;

    str = format(str, name, actionName, controllerName, moduleName);
    return str;
}

string __createCallActionMethod(T, string moduleName)()
{
    import std.traits;
    import std.format;
    import std.string;
    import std.conv;
    

    string str = `
        import hunt.http.server.HttpServerRequest;
        import hunt.http.server.HttpServerResponse;
        import hunt.http.routing.RoutingContext;
        import hunt.http.HttpBody;
        import hunt.logging.ConsoleLogger;
        import hunt.validation.ConstraintValidatorContext;
        import kerisy.middleware.MiddlewareInterface;
        import std.demangle;

        void callActionMethod(string methodName, RoutingContext context) {
            _routingContext = context;
            HttpBody rb;
            version (HUNT_FM_DEBUG) logDebug("methodName=", methodName);
            import std.conv;

            switch(methodName){
    `;

    foreach (memberName; __traits(allMembers, T))
    {
        // TODO: Tasks pending completion -@zhangxueping at 2019-09-24T11:47:45+08:00
        // Can't detect the error: void test(error);
        // pragma(msg, "memberName: ", memberName);
        static if (is(typeof(__traits(getMember, T, memberName)) == function))
        {
            // pragma(msg, "got: ", memberName);

            enum _isActionMember = IsActionMember(memberName);
            static foreach (currentMethod; __traits(getOverloads, T, memberName))
            {
                // alias RT = ReturnType!(t);

                //alias pars = ParameterTypeTuple!(t);
                static if (hasUDA!(currentMethod, Action) || _isActionMember) {
                    str ~= indent(2) ~ "case \"" ~ memberName ~ "\": {\n";
                    str ~= indent(4) ~ "_currentActionName = \"" ~ currentMethod.mangleof ~ "\";";

                    // middleware
                    str ~= `auto middleResponse = this.HandleMiddlewares("`~ memberName ~ `");`;

                    //before
                    str ~= q{
                        if (middleResponse !is null) {
                            // _routingContext.response = response.httpResponse;
                            response = middleResponse;
                            return;
                        }

                        if (!this.Before()) {
                            // _routingContext.response = response.httpResponse;
                            // response = middleResponse;
                            return;
                        }
                    };

                    // Action parameters
                    auto params = ParameterIdentifierTuple!currentMethod;
                    string paramString = "";

                    static if (params.length > 0) {
                        import std.conv : to;

                        string varName = "";
                        alias paramsType = Parameters!currentMethod;

                        static foreach (int i; 0..params.length)
                        {
                            varName = TempVarName ~ i.to!string;

                            static if (paramsType[i].stringof == "string") {
                                str ~= indent(2) ~ "string " ~ varName ~ " = request.get(\"" ~ params[i] ~ "\");\n";
                            } else static if (isNumeric!(paramsType[i])) {
                                str ~= "\t\tauto " ~ varName ~ " = this.ProcessGetNumericString(request.get(\"" ~ 
                                    params[i] ~ "\")).to!" ~ paramsType[i].stringof ~ ";\n";
                            } else static if(is(paramsType[i] : Form)) {
                                str ~= "\t\tauto " ~ varName ~ " = request.bindForm!" ~ paramsType[i].stringof ~ "();\n";
                            } else {
                                str ~= "\t\tauto " ~ varName ~ " = request.get(\"" ~ params[i] ~ "\").to!" ~ 
                                        paramsType[i].stringof ~ ";\n";
                            }

                            paramString ~= i == 0 ? varName : ", " ~ varName;
                            // varName = "";
                        }
                    }

                    // Parameters validation
                    // https://forum.dlang.org/post/bbgwqvvausncrkukzpui@forum.dlang.org
                    str ~= indent(3) ~ `_actionValidators["` ~ currentMethod.mangleof ~ 
                        `"] = (ConstraintValidatorContext context) {` ~ "\n";

                    static if(is(typeof(currentMethod) allParams == __parameters)) {
                        str ~= indent(4) ~ "version(HUNT_DEBUG) info(`Validating in " ~  memberName ~ 
                            ", the prototype is " ~ typeof(currentMethod).stringof ~ ". `); " ~ "\n";
                        // str ~= indent(4) ~ `version(HUNT_DEBUG) infof("Validating in %s", demangle(_currentActionName)); ` ~ "\n";                        

                        static foreach(i, _; allParams) {{
                            alias thisParameter = allParams[i .. i + 1]; 
                            alias udas =  __traits(getAttributes, thisParameter);
                            enum ident = __traits(identifier, thisParameter);

                            str ~= "\n" ~ makeParameterValidation!(TempVarName ~ i.to!string, ident, 
                                thisParameter, udas) ~ "\n"; 
                         }}
                    }

                    str ~= indent(3) ~ "};\n";

                    // Call the Action
                    static if (is(ReturnType!currentMethod == void)) {
                        str ~= "\t\tthis." ~ memberName ~ "(" ~ paramString ~ ");\n";
                    } else {
                        str ~= "\t\t" ~ ReturnType!currentMethod.stringof ~ " result = this." ~ 
                                memberName ~ "(" ~ paramString ~ ");\n";

                        static if (is(ReturnType!currentMethod : Response)) {
                            str ~= "\t\t this.response = result;\n";
                        } else {
                            static if(is(T : RestController)) {
                                str ~="\t\tthis.response.setRestContent(result);";
                            } else {
                                str ~="\t\tthis.response.SetContent(result);";
                            }
                        }
                    }

                    static if(hasUDA!(currentMethod, Action) || _isActionMember) {
                        str ~= "\n\t\tthis.After();\n";
                    }

                    str ~= "\n\t\tbreak;\n\t}\n";
                }
            }
        }
    }

    str ~= "\tdefault:\n\tbreak;\n\t}\n\n";
    str ~= "}";

    return str;
}


string makeParameterValidation(string varName, string paraName, paraType, UDAs ...)() {
    string str;
    // = "\ninfof(\"" ~ symbol.stringof ~ "\");";

    static foreach(uda; UDAs) {
        static if(is(typeof(uda) == Max)) {
            str ~= `{
                MaxValidator validator = new MaxValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == Min)) {
            str ~= `{
                MinValidator validator = new MinValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == AssertFalse)) {
            str ~= `{
                AssertFalseValidator validator = new AssertFalseValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == AssertTrue)) {
            str ~= `{
                AssertTrueValidator validator = new AssertTrueValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == Email)) {
            str ~= `{
                EmailValidator validator = new EmailValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == Length)) {
            str ~= `{
                LengthValidator validator = new LengthValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == NotBlank)) {
            str ~= `{
                NotBlankValidator validator = new NotBlankValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == NotEmpty)) {
            str ~= `{
                auto validator = new NotEmptyValidator!` ~ paraType.stringof ~`();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == Pattern)) {
            str ~= `{
                PatternValidator validator = new PatternValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == Size)) {
            str ~= `{
                SizeValidator validator = new SizeValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }

        static if(is(typeof(uda) == Range)) {
            str ~= `{
                RangeValidator validator = new RangeValidator();
                validator.initialize(` ~ uda.stringof ~ `);
                validator.setPropertyName("` ~ paraName ~ `");
                validator.isValid(`~ varName ~`, context);
            }`;
        }
    }

    return str;
}

alias QueryParameterValidator = void delegate(ConstraintValidatorContext);

string __createRouteMap(T, string moduleName)()
{

    enum len = "Controller".length;
    enum controllerName = moduleName[0..$-len];

    // The specification for ActionID: 
    // 1) controller.[{group}.]{name}controller
    //      controller.admin.IndexController
    //      controller.IndexController
    // 
    // 2) component.{component-name}.controller.{group}.{name}controller
    //      component.system.controller.admin.DashboardController

    enum string[] parts = moduleName.split(".");
    // string groupName = "default";

    static if(parts.length == 3) {
        // controller.admin.DashboardController
        enum GroupName = parts[1];
    } else static if(parts.length == 5) {
        // component.system.controller.admin.DashboardController
        enum GroupName = parts[3];
    } else {
        enum GroupName = "default";
    }

    string str = "";
    foreach (memberName; __traits(allMembers, T))
    {
        // pragma(msg, "memberName: ", memberName);

        static if (is(typeof(__traits(getMember, T, memberName)) == function)) {
            foreach (t; __traits(getOverloads, T, memberName)) {
                static if (hasUDA!(t, Action)) {
                    enum string MemberName = memberName;
                } else static if (IsActionMember(memberName)) {
                    enum string MemberName = memberName[0 .. $ - actionNameLength];
                } else {
                    enum string MemberName = "";
                }

                static if(MemberName.length > 0) {
                    str ~= "\n\tregisterRouteHandler(\"" ~ controllerName ~ "." ~ T.stringof ~ "." ~ MemberName
                        ~ "\", (context) { 
                            context.groupName = \"" ~ GroupName ~ "\";
                            callHandler!(" ~ T.stringof ~ ",\"" ~ memberName ~ "\")(context);
                    });\n";
                }
            }
        }
    }

    return str;
}

void callHandler(T, string method)(RoutingContext context)
        if (is(T == class) || (is(T == struct) && hasMember!(T, "__CALLACTION__")))
{
    // req.action = method;
    // auto req = context.GetRequest();
    // warningf("group name: %s, Threads: %d", context.groupName(), Thread.getAll().length);

    T controller = new T();

    scope(exit) {
        import hunt.util.ResoureManager;
        ApplicationConfig appConfig = app().Config();
        if(appConfig.http.workerThreads == 0) {
            collectResoure();
        }
        controller.dispose();
        // HUNT_THREAD_DEBUG
        version(HUNT_DEBUG) {
            warningf("Threads: %d, allocatedInCurrentThread: %d bytes", 
                Thread.getAll().length, GC.stats().allocatedInCurrentThread);
        }
        // GC.collect();
    }

    try {
        controller.initializeMiddlewares();
        controller.callActionMethod(method, context);
        controller.Done();
    } catch (Throwable t) {
        error(t);
        Response errorRes = new Response();
        errorRes.DoError(HttpStatus.INTERNAL_SERVER_ERROR_500, t);
        controller.raiseError(errorRes); 
    }
    
    context.end();
}

RoutingHandler getRouteHandler(string str)
{
    return _actions.get(str, null);
}

void registerRouteHandler(string str, RoutingHandler method)
{
    // key: app.controller.Index.IndexController.showString
    version (HUNT_FM_DEBUG) logDebug("Add route handler: ", str);
    _actions[str.toLower] = method;
}

__gshared RoutingHandler[string] _actions;
