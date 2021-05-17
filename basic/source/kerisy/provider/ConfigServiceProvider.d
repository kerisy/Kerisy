module kerisy.provider.ConfigServiceProvider;

import kerisy.application.HostEnvironment;
import kerisy.config.ApplicationConfig;
import kerisy.config.AuthUserConfig;
import kerisy.config.ConfigManager;
import kerisy.provider.ServiceProvider;
import kerisy.Init;
import kerisy.routing;

import hunt.logging.ConsoleLogger;
import poodinis;

import std.array;
import std.file;
import std.path;
import std.parallelism : totalCPUs;
import std.process;
import std.range;


/**
 * 
 */
class ConfigServiceProvider : ServiceProvider {

    private ApplicationConfig appConfig;

    override void register() {
        container.register!(ConfigManager).singleInstance();

        registerApplicationConfig();

        registerRouteConfigManager();

        registerAuthUserConfig();
    }

    protected void registerApplicationConfig() {
        container.register!(ApplicationConfig)(&buildAppConfig).singleInstance();
    }

    private ApplicationConfig buildAppConfig() {
        ConfigManager configManager = container.resolve!(ConfigManager)();
        ApplicationConfig appConfig = configManager.load!(ApplicationConfig);

        checkWorkerThreads(appConfig);

        // update the config item with the environment variable if it exists
        string value = environment.get(ENV_APP_NAME, "");
        if(!value.empty) {
            appConfig.application.name = value;
        }

        // value = environment.get(ENV_APP_VERSION, "");
        // if(!value.empty) {
        //     appConfig.application.version = value;
        // }

        value = environment.get(ENV_APP_LANG, "");
        if(!value.empty) {
            appConfig.application.defaultLanguage = value;
        }

        value = environment.get(ENV_APP_KEY, "");
        if(!value.empty) {
            appConfig.application.secret = value;
        }

        return appConfig;
    }

    private void checkWorkerThreads(ApplicationConfig appConfig) {
        
        // Worker pool
        int minThreadCount = totalCPUs / 4 + 1;
        // if (appConfig.http.workerThreads == 0)
        //     appConfig.http.workerThreads = minThreadCount;

        if (appConfig.http.workerThreads != 0 && appConfig.http.workerThreads < minThreadCount) {
            warningf("It's better to make the worker threads >= %d. The current value is: %d",
                    minThreadCount, appConfig.http.workerThreads);
            // appConfig.http.workerThreads = minThreadCount;
        }

        if (appConfig.http.workerThreads == 1) {
            appConfig.http.workerThreads = 2;
        }

        if(appConfig.http.ioThreads <= 0) {
            appConfig.http.ioThreads = totalCPUs;
        }

        // 0 means to use the IO thread
    }

    protected void registerRouteConfigManager() {
        container.register!(RouteConfigManager)(() {
            ConfigManager configManager = container.resolve!(ConfigManager)();
            ApplicationConfig appConfig = container.resolve!(ApplicationConfig)();
            RouteConfigManager routeConfig = new RouteConfigManager(appConfig);
            routeConfig.BasePath = configManager.hostEnvironment.configPath();

            return routeConfig;
        });
    }

    protected void registerAuthUserConfig() {
        container.register!(AuthUserConfig)(() {
            string userConfigFile = buildPath(APP_PATH, DEFAULT_CONFIG_PATH, DEFAULT_USERS_CONFIG);
            string roleConfigFile = buildPath(APP_PATH, DEFAULT_CONFIG_PATH, DEFAULT_ROLES_CONFIG);
            AuthUserConfig config = AuthUserConfig.load(userConfigFile, roleConfigFile);

            return config;
        }).singleInstance();
    }

    override void boot() {
        AuthUserConfig userConfig = container.resolve!(AuthUserConfig);
    }
}