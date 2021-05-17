module kerisy.provider.ServiceProvider;

import std.concurrency : initOnce;
import poodinis;

/**
 * https://code.tutsplus.com/tutorials/how-to-register-use-laravel-service-providers--cms-28966
 */
abstract class ServiceProvider {

    package(kerisy) shared DependencyContainer _container;

    shared(DependencyContainer) container() {
        return _container;
    }

    /**
     * Register any application services.
     *
     * @return void
     */
    void register();

    /**
     * Bootstrap the application events.
     *
     * @return void
     */
    void boot() {
    }
}

private shared DependencyContainer _serviceContainer;

shared(DependencyContainer) serviceContainer() {
    return initOnce!_serviceContainer(new shared DependencyContainer());
}
