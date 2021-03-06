module kerisy.provider.TaskServiceProvider;

import kerisy.config.ApplicationConfig;
import kerisy.provider.ServiceProvider;
import kerisy.queue;
// import kerisy.task;
import hunt.util.worker.Worker;

import hunt.logging.ConsoleLogger;
import poodinis;

import std.path;

/**
 * 
 */
class TaskServiceProvider : ServiceProvider {

    override void register() {
        container.register!(Worker)(&build).singleInstance();
    }

    protected Worker build() {
        ApplicationConfig appConfig = container.resolve!ApplicationConfig();
        TaskQueue queue = container.resolve!TaskQueue();
        return new Worker(queue, appConfig.task.workerThreads);
    }

    override void boot() {
        ApplicationConfig appConfig = container.resolve!ApplicationConfig();
        if(appConfig.queue.enabled) {
            Worker worker = container.resolve!Worker();
            worker.run();
        }
    }

}